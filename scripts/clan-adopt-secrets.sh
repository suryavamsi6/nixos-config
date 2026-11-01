#!/usr/bin/env bash
# Adopt live secret files into the Clan vars store.
#
# Every generator in modules/clan/secrets.nix is adopt-only: it refuses to mint a
# value, because these credentials are already live and entangled (rotating one
# breaks its consumer — see the header of that file). This script does the
# adopting: it reads the current file off the host that owns it and pushes it into
# the local age store with `clan vars set`.
#
# Run it on a machine that has BOTH the store key and a way to read the source:
#
#   export CLAN_AGE_STORE_DIR=$HOME/clan-secrets
#   ./scripts/clan-adopt-secrets.sh --list          # what is missing, from where
#
# The restic client env additionally needs the repository password, which exists
# nowhere on disk and cannot be read back off the server; pass it in when adopting:
#
#   RESTIC_REPO_PASSWORD=... ./scripts/clan-adopt-secrets.sh homelab
#   RESTIC_REPO_PASSWORD=... ./scripts/clan-adopt-secrets.sh nixos
#
# Without it, the two client targets still adopt everything else and report what is
# missing; they do not mint a password, for the same reason no generator does.
#
# Targets:
#   ./scripts/clan-adopt-secrets.sh homelab         # ssh + sudo, prompts once
#   ./scripts/clan-adopt-secrets.sh nixos           # local sudo, prompts once
#   ./scripts/clan-adopt-secrets.sh raspberry-pi    # root ssh, never prompts
#
# Re-running is safe and idempotent: it always copies the live value, which for an
# already-adopted var is the same value, and it re-normalises a file whose shape
# drifted (e.g. `environment.KEY: value` from `incus config show` becomes `KEY=value`,
# which is what the consumers grep for).
#
# The `homelab` and `nixos` targets need a sudo password (neither host has
# passwordless sudo — see `interactiveSudo` in modules/clan/deploy.nix), so they
# prompt for it once per host and must be run from a real terminal. They are the
# only two that cannot be scripted; `raspberry-pi` reads over a root ssh and is
# safe to run non-interactively.
#
# `--list` is the source of truth for what still needs adopting; it asks Clan, not
# this script's opinion:
#
#   clan vars check <machine>
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

MACHINES=(homelab nixos raspberry-pi)

# ── helpers ───────────────────────────────────────────────────────────────────

# Every source goes through this: strip CR (an ssh pty inserts them, and a stray
# `\r` inside a bcrypt hash or an env value silently breaks the consumer), then
# normalise `KEY=value`, `environment.KEY: value`, and `KEY: "quoted"` into
# `KEY=value`, dropping comments and blanks. Sources are inconsistent: container
# configs come from `incus config show --expanded`, service env files from
# systemd, so the store always gets one shape.
normalise() {
  tr -d '\r' |
  sed -nE \
    -e 's/^[[:space:]]*environment\.([A-Za-z_][A-Za-z0-9_]*):[[:space:]]*(.*)$/\1=\2/p' \
    -e 's/^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*[:=][[:space:]]*(.*)$/\1=\2/p' |
    sed -E 's/^([A-Za-z_][A-Za-z0-9_]*=)"(.*)"$/\1\2/; s/^([A-Za-z_][A-Za-z0-9_]*=)'"'"'(.*)'"'"'$/\1\2/'
}

require_keys() { # require_keys <label> <key> [key…]  (reads the normalised text)
  local label=$1; shift
  local body; body=$(cat)
  local missing=()
  for k in "$@"; do
    grep -qE "^${k}=" <<<"$body" || missing+=("$k")
  done
  if [ ${#missing[@]} -gt 0 ]; then
    echo "  ${label}: refusing — missing ${missing[*]}" >&2
    return 1
  fi
  printf '%s' "$body"
}

adopt() { # adopt <machine> <generator/file> <normalised body>
  local machine=$1 var=$2 body=$3
  if [ -z "$body" ]; then
    echo "  ${var}: empty source, skipped" >&2
    return 1
  fi
  # Idempotency is decided by the stored value, not by a flag: re-running must be a
  # no-op so this is safe to call from a boot-time hook or after every pull.
  local current
  current=$(clan vars get "$machine" "$var" 2>/dev/null || true)
  if [ "$current" = "$body" ]; then
    echo "  ${var}: already adopted, unchanged"
    return 0
  fi
  printf '%s\n' "$body" | clan vars set "$machine" "$var" >/dev/null 2>&1
  # Read back: `clan vars set` succeeding is not the same as the store holding what
  # was intended (a truncated pipe or a filtered-out line both "succeed").
  local stored
  stored=$(clan vars get "$machine" "$var" 2>/dev/null || true)
  if [ "$stored" != "$body" ]; then
    echo "  ${var}: read-back MISMATCH — not stored as sent" >&2
    return 1
  fi
  echo "  ${var}: adopted ($(wc -l <<<"$body") key(s), verified)"
}

# Why this shape and not the obvious ones — four approaches, all wrong, kept so they
# are not tried again:
#
#   1. `sudo -v` on one ssh, `sudo cat` on the next -> "sudo: a password is required".
#      sudo caches its credential per login *session*, and ssh shares no session between
#      two connections, so the second connection starts unauthenticated.
#   2. `ssh -t host "sudo cat file"` inside `$(…)`  -> deadlocks. The pty exists, but
#      stdout is the pipe command substitution created, so sudo has somewhere to prompt
#      and nowhere to write.
#   3. `ssh -T host "sudo cat file"`                -> "sudo: a terminal is required".
#      Without a pty sudo refuses to read a password even when fd 0 is a real terminal.
#   4. `ssh -T host "sudo -S ..."` with the terminal left on stdin -> hangs forever.
#      Inside `$(…)` fd 0 is the substitution's pipe, so the password is never read, and
#      because it looks like a terminal nothing fails fast. This one looks like success.
#
# What works, and needs no terminal on stdin at all: ask the user once, reading from
# /dev/tty *explicitly* (an explicit redirect beats the inherited pipe, so this is the
# only form that survives being wrapped in `$(…)`), then carry the password in a
# variable and pipe it to `sudo -S` per host. `sudo -S` reads a password from a pipe
# happily — it is only sudo's own prompt that needs a tty, and `-S` removes the prompt.
#
#   fetch <host> <path> <outfile>   pipe $SUDO_PW to `sudo -S`, capture the file
#   fetch_local <path> <outfile>    same, without ssh
#   fetch_pi <path> <outfile>       root ssh, no sudo, so no password anywhere
# Fails when the remote read fails, rather than leaving an empty file that
# require_keys would then blame on the wrong thing. `sudo -S` reports a bad
# password on stderr with a non-zero status, which is what this propagates.
fetch() {
  printf '%s\n' "$SUDO_PW" | ssh -T "$1" "sudo -S -p '' cat $2" > "$3"
}
fetch_local() {
  printf '%s\n' "$SUDO_PW" | sudo -S -p '' cat "$1" > "$2"
}
fetch_pi() { ssh -o BatchMode=yes root@192.168.0.105 "cat $1" > "$2"; }

# Assemble a client's restic env from the two halves that actually exist, instead of
# from /var/lib/restic-backups/env (which neither host has ever had — see docs).
#
#   restic-client/env = RESTIC_PASSWORD
#                     + RESTIC_REST_<HOST>_{USERNAME,PASSWORD}  (from the pi's clients.env)
#
# The second half is already in the store. The first is not: it is the repository
# password, it is chosen when the repo is created, and nothing on the pi reveals it.
# So this refuses with an actionable message rather than minting a value that would
# not match, in line with every other generator in modules/clan/secrets.nix being
# adopt-only. Pass it in to proceed:
#
#   RESTIC_REPO_PASSWORD=... ./scripts/clan-adopt-secrets.sh homelab
adopt_restic_client() { # adopt_restic_client <machine> <RESTIC_REST_HOST prefix>
  local machine=$1 prefix=$2 clients body
  clients=$(clan vars get raspberry-pi restic-htpasswd/clients-env 2>/dev/null || true)
  if [ -z "$clients" ]; then
    echo "  restic-client/env: cannot assemble — raspberry-pi" >&2
    echo "    restic-htpasswd/clients-env is not in the store. Run" >&2
    echo "    ./scripts/clan-adopt-secrets.sh raspberry-pi first." >&2
    return 1
  fi

  local user pass
  user=$(sed -nE "s/^${prefix}_USERNAME=(.*)$/\1/p" <<<"$clients")
  pass=$(sed -nE "s/^${prefix}_PASSWORD=(.*)$/\1/p" <<<"$clients")
  if [ -z "$user" ] || [ -z "$pass" ]; then
    echo "  restic-client/env: ${prefix}_{USERNAME,PASSWORD} missing from clients-env" >&2
    return 1
  fi

  if [ -z "${RESTIC_REPO_PASSWORD:-}" ]; then
    echo "  restic-client/env: NOT adopted — needs the repository password" >&2
    echo "    ${prefix}_USERNAME/PASSWORD are in the store, RESTIC_PASSWORD is not." >&2
    echo "    Nothing on the pi can supply it: it is set when the restic repo is" >&2
    echo "    initialised. If this is a new repo, choose one and pass it in:" >&2
    echo "      RESTIC_REPO_PASSWORD=... $0 $machine" >&2
    echo "    If a repo should already exist, check it was never initialised — the" >&2
    echo "    nightly unit skips on its own while this var is absent." >&2
    return 1
  fi

  body=$(printf 'RESTIC_PASSWORD=%s\n%s_USERNAME=%s\n%s_PASSWORD=%s\n' \
    "$RESTIC_REPO_PASSWORD" "$prefix" "$user" "$prefix" "$pass")
  adopt "$machine" restic-client/env "$body"
}

# Called once per branch, not per file. Prompts from /dev/tty so it works from a script,
# a function, or a command substitution; fails loudly rather than hanging when there is
# genuinely no terminal attached.
ask_password() {
  if [ -t 0 ]; then
    IFS= read -rsp "sudo password: " SUDO_PW; echo
  elif (: < /dev/tty) 2>/dev/null; then
    IFS= read -rsp "sudo password: " SUDO_PW < /dev/tty; echo
  else
    echo "ERROR: this target needs a sudo password and there is no terminal." >&2
    echo "       run it yourself, or use the raspberry-pi target (root ssh, no sudo)." >&2
    return 1
  fi
  if [ -z "${SUDO_PW:-}" ]; then
    echo "ERROR: empty password" >&2
    return 1
  fi
}

case "${1:-}" in
  --list)
    # `clan vars check` without the store unset prints "externalStore is enabled, but
    # CLAN_AGE_STORE_DIR is not set" — which is easy to mistake for "nothing missing".
    if [ -z "${CLAN_AGE_STORE_DIR:-}" ]; then
      echo "CLAN_AGE_STORE_DIR is not set. Everything below would look adopted." >&2
      echo "  export CLAN_AGE_STORE_DIR=\$HOME/clan-secrets" >&2
      echo "  bash $0 --list" >&2
      exit 1
    fi
    for m in "${MACHINES[@]}"; do
      echo "== ${m}"
      clan vars check "$m" 2>&1 | sed -n '/Missing secret vars/,$p' | sed '1d;s/^/  /' || true
    done
    cat <<'EOF'

Run the sudo targets from an interactive terminal (`homelab`, `nixos`).

Adoption sources (see the table in this script):
  homelab       grok-oauth/secrets-env     /var/lib/grok-oauth-proxy/secrets.env
                searx-secret/secret-env    /var/lib/searx/secret.env
                restic-client/env          /var/lib/restic-backups/env
  nixos         restic-client/env          /var/lib/restic-backups/env
  raspberry-pi  restic-htpasswd/htpasswd   /var/lib/restic-rest/htpasswd
                restic-htpasswd/clients-env /var/lib/restic-rest/clients.env
EOF
    exit 0
    ;;

  homelab)
    ask_password || exit 1
    # One sudo prompt, then every file is read in the same shape: fetch to a temp
    # file, normalise, require the expected keys, adopt. Temp files are 0600 and
    # removed on exit.
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

    # grok-oauth-proxy: ADMIN_API_KEY is injected by Caddy on /grok, GROK_ADMIN_KEY
    # is what Gatus sends (same value), GROK_CLIENT_KEY is the gate credential
    # Bifrost carries.
    fetch homelab.home.arpa /var/lib/grok-oauth-proxy/secrets.env "$tmp/grok" &&
      adopt homelab grok-oauth/secrets-env \
        "$(normalise < "$tmp/grok" |
          require_keys grok-oauth ADMIN_API_KEY GROK_ADMIN_KEY GROK_CLIENT_KEY)"

    # SearXNG: systemd EnvironmentFile, so the KEY= prefix is load-bearing.
    fetch homelab.home.arpa /var/lib/searx/secret.env "$tmp/searx" &&
      adopt homelab searx-secret/secret-env \
        "$(normalise < "$tmp/searx" | require_keys searx SEARX_SECRET_KEY)"

    # restic-client: there is no /var/lib/restic-backups/env on either host, and
    # there never was — the topologies never matched. The client env is assembled
    # from the two halves that do exist:
    #
    #   RESTIC_REST_<HOST>_{USERNAME,PASSWORD}  already in the store as the pi's
    #                                          restic-htpasswd/clients-env
    #   RESTIC_PASSWORD                        the repository password, shared by
    #                                          every client; NOT recoverable from
    #                                          the server and not in the store yet
    #
    # Until RESTIC_PASSWORD is supplied there is nothing to adopt, and the nightly
    # unit skips on its own (`ExecCondition = test -r <envFile>`), so this is not
    # urgent — it just means no backup has ever run.
    adopt_restic_client homelab RESTIC_REST_HOMELAB
    ;;

  nixos)
    ask_password || exit 1
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
    adopt_restic_client nixos RESTIC_REST_NIXOS
    ;;

  raspberry-pi)
    # No sudo anywhere: this reads over a root ssh, so nothing prompts.
    # The bcrypt htpasswd is what rest-server authenticates against; clients-env is
    # the operator-readable plaintext copy both clients take their password from.
    # Neither is derivable, so both are copied verbatim (no normalising).
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
    fetch_pi /var/lib/restic-rest/htpasswd "$tmp/htpasswd" &&
      adopt raspberry-pi restic-htpasswd/htpasswd \
        "$(tr -d '\r' < "$tmp/htpasswd" | grep -E '^[^:]+:\$2[aby]\$' ||
           echo 'REFUSED: no bcrypt lines' >&2)"
    fetch_pi /var/lib/restic-rest/clients.env "$tmp/clients" &&
      adopt raspberry-pi restic-htpasswd/clients-env \
        "$(normalise < "$tmp/clients" |
          require_keys clients-env RESTIC_REST_NIXOS_USERNAME RESTIC_REST_NIXOS_PASSWORD \
            RESTIC_REST_HOMELAB_USERNAME RESTIC_REST_HOMELAB_PASSWORD)"
    ;;

  *)
    sed -nE '2,/^set -euo/{s/^# ?//;p}' "${BASH_SOURCE[0]}" | sed -n '/Adopt live/,$p'
    exit 1
    ;;
esac

echo
echo "Upload before any deploy that changes a secret var:"
echo "  clan vars upload homelab"
echo "  clan vars upload raspberry-pi"
