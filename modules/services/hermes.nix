# Hermes agent in an Ubuntu 24.04 Incus container.
#
# Extracted from modules/hosts/nixos-homelab.nix (§7 item 8.3 of
# plans/clan-deploy-rs-migration.md). A provisioning oneshot, not a nixpkgs
# module: the agent installs itself inside an Ubuntu guest.
#
# Migrated off the pi, where it ran as user state under ~/.hermes plus
# host-side nix-ld/cert.pem workarounds. The aarch64 toolchain pieces are
# excluded on purpose — the installer restages them for x86_64; only
# architecture-neutral state (config.yaml, .env, sessions, memories, skills,
# pairing, cron, hooks) moves over.
#
# It reaches Bifrost directly over incusbr0 at 10.110.0.100:8080 rather than
# through bifrost.home.arpa, which is Caddy on the host and unnecessary for
# container-to-container traffic. Hermes still records the retired LiteLLM
# provider name in its cleanup list; that is data, not a live dependency.
#
# The dashboard is a separate systemd *user* unit pushed into the guest,
# because upstream does not start it with the gateway service
# (NousResearch/hermes-agent#16702). %h expands to /home/hermes.
#
# LIVE DATA: the container keeps ~/.hermes inside its own volume, plus a host
# bind of /home/surya/hermes-work at /home/hermes/work. Do not move either.
{ lib, ... }:
{
  options.flake.modules.nixos.hermes = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        vars = config.clan.core.vars.generators;
        dashboardFile = vars.hermes-dashboard.files.dashboard-env.path;
        bifrostKeyFile = vars.hermes-bifrost-key.files.bifrost-vk-env.path;

        # systemd *user* unit for the dashboard inside the incus-hermes
        # container, pushed in by the provisioning unit below. Upstream does not
        # start the dashboard with its gateway service
        # (NousResearch/hermes-agent#16702), so it gets its own unit; %h expands
        # to /home/hermes under the user manager.
        hermesDashboardUnit = pkgs.writeText "hermes-dashboard.service" ''
          [Unit]
          Description=Hermes web dashboard (port 9119)

          [Service]
          EnvironmentFile=%h/.hermes/.env
          ExecStart=%h/.local/bin/hermes dashboard --host 0.0.0.0 --port 9119 --no-open
          Restart=on-failure
          RestartSec=5
          RestartPreventExitStatus=78

          [Install]
          WantedBy=default.target
        '';
      in
      {
        systemd.services.incus-hermes = {
          description = "Provision Hermes agent Incus container";
          wantedBy = [ "multi-user.target" ];
          after = [
            "incus.service"
            "network-online.target"
          ];
          wants = [ "network-online.target" ];
          requires = [
            "incus.service"
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          path = [
            pkgs.incus
            pkgs.gnugrep
            pkgs.coreutils
            pkgs.gnutar
            pkgs.openssl
          ];
          script = ''
            set -euo pipefail
            exists=no
            if incus list --format csv -c n | grep -qx hermes; then
              exists=yes
            fi

            if [ "$exists" = no ]; then
              incus launch images:ubuntu/24.04 hermes \
                -c boot.autostart=true \
                -c limits.memory=8GiB \
                -c limits.cpu=6
              incus config device set hermes eth0 ipv4.address=10.110.0.50 ||
                incus config device override hermes eth0 ipv4.address=10.110.0.50
              sleep 15
              incus exec hermes -- cloud-init status --wait >/dev/null 2>&1 || true
              incus exec hermes -- apt-get update -qq
              # libX*/xkb: the prebuilt cua-driver (computer-use helper)
              # links against them; without the libs its staged
              # verification exits 127 and the tool is skipped.
              incus exec hermes -- apt-get install -y -qq git curl ca-certificates \
                libxi6 libxrandr2 libxrender1 libx11-6 libxext6 \
                libxkbcommon0 libxkbcommon-x11-0

              # Dedicated user; the agent's whole world is its $HOME.
              incus exec hermes -- useradd -m -s /bin/bash hermes
              incus exec hermes -- bash -c \
                'echo "hermes ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/hermes && chmod 440 /etc/sudoers.d/hermes'
            fi

            # `launch` only sets limits at creation, so a container that
            # predates these caps keeps its old ones until reconciled
            # here. Raising memory or cpu takes effect live (cgroup),
            # no restart.
            if [ "$(incus config get hermes limits.memory)" != "8GiB" ]; then
              incus config set hermes limits.memory=8GiB
            fi
            if [ "$(incus config get hermes limits.cpu)" != "6" ]; then
              incus config set hermes limits.cpu=6
            fi

            # Bot Screen display stack: Xvnc + Xfce give the bot its own X
            # display, and at-spi2-core is what cua-driver's ax_capability
            # probes for (org.a11y.Bus activation); libatspi2 alone is not
            # enough. Deliberately not upstream's xfce4 metapackage — it
            # pulls the screensaver, power manager and polkit agent that
            # lock or prompt a headless session. Gated on Xvnc so an
            # existing container picks this up on the next switch without
            # re-running apt on every activation.
            if ! incus exec hermes -- test -x /usr/bin/Xvnc; then
              incus exec hermes -- apt-get update -qq
              incus exec hermes -- env DEBIAN_FRONTEND=noninteractive \
                apt-get install -y -qq --no-install-recommends \
                tigervnc-standalone-server xfce4-panel xfwm4 xfdesktop4 \
                xfce4-settings xfce4-terminal dbus-x11 x11-xserver-utils \
                x11-utils x11-xkb-utils xauth fonts-dejavu-core \
                at-spi2-core
            fi

            # Must exist before either the state import or the auth append
            # writes into it: on a fresh install the tree only appears at
            # the installer's config stage, and `>> ~/.hermes/.env` fails
            # with ENOENT when the parent is missing.
            incus exec hermes -- install -d -o hermes -g hermes -m 700 /home/hermes/.hermes

            # Import migrated state before the first install; the installer
            # keeps an existing config.yaml/.env and only fills gaps.
            state=/var/lib/incus/hermes/state
            if [ -d "$state" ] && [ -n "$(ls -A "$state")" ]; then
              incus exec hermes -- install -d -o hermes -g hermes /home/hermes/.hermes
              tar -C "$state" -cf - . | incus exec hermes -- tar -C /home/hermes/.hermes --no-same-owner -xf -
              incus exec hermes -- chown -R hermes:hermes /home/hermes/.hermes
            fi

            # Generated once, never rotated (rotation would lock out saved
            # Hermes Desktop logins) and never printed. The value now lives in
            # the `hermes-dashboard` Clan var; the old file is kept untouched as
            # the rollback path and only marked (§6.3).
            install -d -m 700 /var/lib/incus/hermes
            auth=/var/lib/incus/hermes/dashboard.env
            if [ -s "$auth" ]; then
              : > /var/lib/incus/hermes/.dashboard-migrated-to-clan
            fi
            auth=${dashboardFile}
            incus exec hermes -- sudo -u hermes -- bash -c \
              'grep -q "^HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=" ~/.hermes/.env 2>/dev/null || { printf "\n# dashboard auth for hermes.home.arpa\n"; cat; } >> ~/.hermes/.env' < "$auth"
            incus exec hermes -- sudo -u hermes -- chmod 600 /home/hermes/.hermes/.env

            # --non-interactive skips the TTY setup/gateway stages; on a
            # fresh (non-migrated) install run `hermes setup` inside the
            # container afterwards for provider keys. Install once: the
            # update path afterwards is `hermes update` in the container
            # (same as the pi setup), not a rerun of this unit.
            if ! incus exec hermes -- sudo -u hermes -- test -x /home/hermes/.local/bin/hermes; then
              incus exec hermes -- sudo -iu hermes -- \
                bash -c 'curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --non-interactive'
            fi

            # Gateway: upstream-managed systemd service. Linger keeps the
            # user services alive without a login session.
            incus exec hermes -- loginctl enable-linger hermes
            uid=$(incus exec hermes -- id -u hermes | tr -d '\r\n ')
            incus exec hermes -- systemctl start "user@$uid.service" 2>/dev/null || true
            incus exec hermes -- sudo -iu hermes -- hermes gateway install --if-missing </dev/null

            # Dashboard: its own user unit, pushed from the Nix store so
            # the definition stays in this file.
            incus exec hermes -- install -d -o hermes -g hermes /home/hermes/.config/systemd/user
            incus file push ${hermesDashboardUnit} \
              hermes/home/hermes/.config/systemd/user/hermes-dashboard.service
            incus exec hermes -- chown hermes:hermes /home/hermes/.config/systemd/user/hermes-dashboard.service
            incus exec hermes -- sudo -u hermes -- \
              env XDG_RUNTIME_DIR=/run/user/$uid systemctl --user daemon-reload
            incus exec hermes -- sudo -u hermes -- \
              env XDG_RUNTIME_DIR=/run/user/$uid systemctl --user enable --now hermes-dashboard.service

            # The retired phone bridge was installed as guest user units, so
            # removing its host module alone would leave both processes running.
            # Stop and remove only those units; retain their data and keys for
            # rollback. Re-running this after the first migration is a no-op.
            bridge_removed=no
            for unit in hermes-bridge.service hermes-bridge-backend.service; do
              if incus exec hermes -- test -e "/home/hermes/.config/systemd/user/$unit"; then
                incus exec hermes -- sudo -u hermes -- \
                  env XDG_RUNTIME_DIR=/run/user/$uid systemctl --user disable --now "$unit"
                incus exec hermes -- rm -f "/home/hermes/.config/systemd/user/$unit"
                bridge_removed=yes
              fi
            done
            if [ "$bridge_removed" = yes ]; then
              incus exec hermes -- sudo -u hermes -- \
                env XDG_RUNTIME_DIR=/run/user/$uid systemctl --user daemon-reload
            fi

            # Computer use on a chat-only bot: auto_start brings the Bot
            # Screen up on the first computer_use call instead of waiting
            # for someone to press Start in the dashboard. `hermes config
            # set` merges YAML, so this is idempotent and leaves the rest of
            # config.yaml (models, platforms, dashboard auth) untouched. The
            # gateway reads config at startup, so restart it when the value
            # actually changed.
            gateway_restarted=no
            restart_reasons=""

            # --- Point Hermes at Bifrost ---
            # Bifrost replaced the LiteLLM gateway, which is gone. Hermes
            # reaches the Bifrost container directly over incusbr0 at
            # 10.110.0.100:8080 (the same address its own health check in
            # Gatus uses); bifrost.home.arpa is Caddy on the host and is
            # not needed for container-to-container traffic.
            #
            # The virtual key is a real secret and never enters the flake. Since the
            # Clan migration its home is the `hermes-bifrost-key` var, but
            # ~/.hermes/.env inside the container stays the *authority*: an earlier
            # version preferred the host-side file and minted a random key when .env
            # had none, and that key existed in no Bifrost virtual-key record, so every
            # gateway call 401'd. So the order is: .env -> var -> legacy file, and if all
            # three are empty the unit reports it instead of minting a key nobody can use.
            #
            # The legacy file is kept (never rewritten) as the rollback path and is
            # appended to ~/.hermes/.env only when that file lacks the key.
            vk=/var/lib/incus/hermes/bifrost-vk.env
            install -d -m 700 /var/lib/incus/hermes
            live=$(incus exec hermes -- sudo -u hermes -- bash -c \
              'sed -n "s/^BIFROST_API_KEY=//p" ~/.hermes/.env 2>/dev/null | head -1' \
              | tr -d '\r\n' || true)
            if [ -z "$live" ] && [ -s ${bifrostKeyFile} ]; then
              live=$(sed -n 's/^BIFROST_API_KEY=//p' ${bifrostKeyFile} | head -1 | tr -d '\r\n' || true)
            fi
            if [ -z "$live" ] && [ -s "$vk" ]; then
              live=$(sed -n 's/^BIFROST_API_KEY=//p' "$vk" | head -1 | tr -d '\r\n' || true)
            fi
            # Last resort only: the var, the container's .env and the legacy file all
            # came up empty, which means this container has never had a key. Minting
            # here would create a key that exists in no Bifrost virtual-key record, so
            # it is reported and skipped — the operator decides.
            if [ -z "$live" ]; then
              echo "WARNING: no BIFROST_API_KEY in ~/.hermes/.env, hermes-bifrost-key," \
                   "or the legacy bifrost-vk.env; leaving the gateway unconfigured." \
                   "Give Hermes a key that is already a Bifrost virtual key." >&2
              live=""
            fi
            # The var file is 0400 root:root and not writable here, so the
            # derived value is printed for the operator once instead.
            if [ -n "$live" ] && ! sed -n 's/^BIFROST_API_KEY=//p' ${bifrostKeyFile} 2>/dev/null | grep -qx "$live"; then
              echo "hermes-bifrost-key differs from the live key; adopt it with:" >&2
              echo "  incus exec hermes -- sudo -u hermes -- grep BIFROST_API_KEY ~/.hermes/.env" >&2
              echo "  clan vars set homelab hermes-bifrost-key/bifrost-vk-env" >&2
            fi
            unset live
            # Seed ~/.hermes/.env from whichever source exists: the Clan var is the
            # home now, the legacy file is the rollback. Both are already
            # `BIFROST_API_KEY=<key>` shaped, and the loop only appends keys the
            # container does not already have, so the container stays authoritative.
            key_src=$vk
            if [ -s ${bifrostKeyFile} ]; then key_src=${bifrostKeyFile}; fi
            if [ -s "$key_src" ]; then
              vk_added=$(incus exec hermes -- sudo -u hermes -- bash -c '
              env=~/.hermes/.env; touch "$env"; added=0
              while IFS= read -r line; do
                [ -n "$line" ] || continue
                if ! grep -q "^''${line%%=*}=" "$env"; then
                  printf "\n# Bifrost gateway (replaced LiteLLM)\n" >> "$env"
                  printf "%s\n" "$line" >> "$env"; added=1
                fi
              done
              chmod 600 "$env"; echo "$added"' < "$key_src" | tr -d '\r\n')
              if [ "$vk_added" = 1 ]; then
                restart_reasons="$restart_reasons bifrost_api_key"
              fi
            fi

            # Gateway address, default model, provider transport and the
            # retired provider entries. `hermes config get` is the
            # idempotency probe so a settled config is not rewritten on
            # every switch.
            hermes_cfg() { incus exec hermes -- sudo -u hermes -H /home/hermes/.local/bin/hermes "$@"; }
            want_provider=bifrost
            want_model=openrouter/z-ai/glm-5.3-flash
            want_api=http://10.110.0.100:8080/v1
            # `config get` exits 1 for an unset key, and under
            # `set -euo pipefail` an assignment from a failing command
            # substitution aborts the script. Every probe below therefore
            # ends in `|| true`; the empty result is the "not set" signal.
            got_api=$(hermes_cfg config get providers.bifrost.api 2>/dev/null | tr -d '\r\n' || true)
            if [ "$got_api" != "$want_api" ]; then
              hermes_cfg config set providers.bifrost.api "$want_api" >/dev/null
              hermes_cfg config set providers.bifrost.key_env BIFROST_API_KEY >/dev/null
              hermes_cfg config set providers.bifrost.transport chat_completions >/dev/null
              restart_reasons="$restart_reasons providers.bifrost"
            fi
            got_model=$(hermes_cfg config get model.default 2>/dev/null | tr -d '\r\n' || true)
            got_prov=$(hermes_cfg config get model.provider 2>/dev/null | tr -d '\r\n' || true)
            got_url=$(hermes_cfg config get model.base_url 2>/dev/null | tr -d '\r\n' || true)
            if [ "$got_model" != "$want_model" ] || [ "$got_prov" != "$want_provider" ] ||
               [ "$got_url" != "$want_api" ]; then
              hermes_cfg config set model.default "$want_model" >/dev/null
              hermes_cfg config set model.provider "$want_provider" >/dev/null
              hermes_cfg config set model.base_url "$want_api" >/dev/null
              hermes_cfg config set model.key_env BIFROST_API_KEY >/dev/null
              hermes_cfg config set model.api_mode chat_completions >/dev/null
              restart_reasons="$restart_reasons model.default"
            fi
            # Drop the retired provider entries so nothing silently falls
            # back to the deleted gateway or to api.z.ai directly.
            for retired in providers.litellm providers.zai; do
              if [ -n "$(hermes_cfg config get "$retired" 2>/dev/null | tr -d '\r\n' || true)" ]; then
                hermes_cfg config unset "$retired" >/dev/null
                restart_reasons="$restart_reasons $retired"
              fi
            done
            if [ "$(incus exec hermes -- sudo -u hermes -H /home/hermes/.local/bin/hermes \
                      config get bot_desktop.auto_start 2>/dev/null | tr -d '\r\n' || true)" != "true" ]; then
              incus exec hermes -- sudo -u hermes -H /home/hermes/.local/bin/hermes \
                config set bot_desktop.auto_start true
              restart_reasons="$restart_reasons bot_desktop.auto_start"
            fi

            # Retire the old phone API listener without rotating or deleting
            # its key. A usable API_SERVER_KEY can auto-enable the adapter
            # even when API_SERVER_ENABLED=false; the explicit platform flag
            # prevents that fallback (upstream issue #87856).
            api_enabled=$(hermes_cfg config get API_SERVER_ENABLED 2>/dev/null | tr -d '\r\n' || true)
            if [ -n "$api_enabled" ] && [ "$api_enabled" != "false" ]; then
              hermes_cfg config set API_SERVER_ENABLED false >/dev/null
              restart_reasons="$restart_reasons api_server_disabled"
            fi
            api_platform=$(hermes_cfg config get platforms.api_server.enabled 2>/dev/null | tr -d '\r\n' || true)
            if [ "$api_platform" != "false" ]; then
              hermes_cfg config set platforms.api_server.enabled false >/dev/null
              restart_reasons="$restart_reasons api_server_platform_disabled"
            fi

            # The gateway reads .env and config.yaml at startup: restart once
            # for everything that changed above.
            if [ -n "$restart_reasons" ]; then
              incus exec hermes -- sudo -u hermes -- \
                env XDG_RUNTIME_DIR=/run/user/$uid systemctl --user restart hermes-gateway.service
              gateway_restarted=yes
            fi

            echo "Hermes container ready; dashboard at http://hermes.home.arpa"
            if [ "$gateway_restarted" = yes ]; then
              echo "hermes-gateway restarted for:$restart_reasons"
            fi

            # Host code workspace: ~/hermes-work bind-mounted at
            # /home/hermes/work, no shift. hermes is 1001:1001 inside
            # (uid 1000 is taken by the Ubuntu image) while surya is
            # 1000:100 on the host, so raw.idmap aligns the ids
            # instead: hermes's writes land as surya:users and vice
            # versa (see also the root subUid/subGid grants above).
            # Deliberately last: a restart must not precede the
            # systemctl --user calls above — seconds after a
            # container restart the user manager's bus socket is
            # not up yet and they fail with "Failed to connect to
            # bus" (seen 2026-10-25, switch gen 34). The map
            # applies at container start, so restart only when it
            # actually changed. Never widen this to all of
            # ~surya: it holds SSH keys and other credentials.
            install -d -o surya -g users -m 700 /home/surya/hermes-work
            idmap=$(incus config get hermes raw.idmap 2>/dev/null || true)
            case "$idmap" in
              *"uid 1000 1001"*"gid 100 1001"*) : ;;
              *)
                printf 'uid 1000 1001\ngid 100 1001\n' |
                  incus config set hermes raw.idmap -
                incus restart hermes
                ;;
            esac
            if ! incus config device show hermes | grep -q '^work:'; then
              incus config device add hermes work disk \
                source=/home/surya/hermes-work path=/home/hermes/work
            fi
          '';
        };
      };
  };
}
