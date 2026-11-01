# Clan vars generators: the homelab's secrets, one generator per file.
#
# These are **NixOS** generators, not flake-level settings: `clan.core.vars.generators`
# is per-machine config, so the definitions live in deferred modules that a host
# imports. `flake.clan.vars.settings` in ./vars.nix only answers "which store, which
# recipients" — this file answers "which secrets exist and who reads them".
#
# Each generator replaces one `*-secrets` oneshot that used to `printf` a value into
# /var/lib on first boot. The consumer reads
#
#   config.clan.core.vars.generators.<gen>.files.<file>.path
#
# which the `age` store resolves to /run/secrets/per-machine/<machine>/<gen>/<file>
# (tmpfs, decrypted by the `setupSecrets` activation script, which Clan wires
# after `specialfs` mounts /run). Nothing sensitive
# is written to a persistent path any more.
#
# ── Every generator is ADOPT-ONLY ──────────────────────────────────────────────
# No generator here mints a value. That is deliberate: `clan vars generate` runs a
# missing generator's `script`, and these files are already live and entangled:
#
#   * rotating the Qdrant key breaks Bifrost's vector-store config and Gatus' probe
#   * rotating Bifrost's encryption key orphans every secret it has stored
#   * rotating a Booklore DB password desynchronises the app from MariaDB
#     (ALTER ROLE on a live DB is a migration step, not a boot side effect)
#   * rotating the Hermes dashboard/API keys signs the phone app and Desktop out
#   * rotating the restic pair 401s every client's nightly push
#
# So the default action is safe — it stops and prints the adoption command instead
# of rotating production. A fresh install adopts too, minting by hand first.
#
# The comments keep the exact original generation recipe, so the value that lands in
# the store is byte-compatible with the file the running system already has.
#
# See plans/clan-deploy-rs-migration.md §6 and docs/homelab.md.
{ lib, ... }:
let
  inherit (lib) concatMapStringsSep mkOption;

  # Adopt-only body: `clan vars generate` prints the commands and exits non-zero
  # rather than rotating a live credential.
  noDefault = generator: lines: {
    script = ''
      {
        echo "${generator} has no safe default: it must match the live value."
        echo "Adopt it with:"
        ${concatMapStringsSep "\n" (l: ''echo "  ${l}"'') lines}
      } >&2
      echo "  then: clan vars upload <machine>" >&2
      exit 1
    '';
  };

  # 0400 root:root under /run/secrets, owned by the `services` phase. 0400 is what
  # the old files were; several services run unprivileged, so a generator that
  # needs a service-owned file overrides `owner`/`group` explicitly.
  secretFile =
    extra:
    {
      neededFor = "services";
      mode = "0400";
    }
    // extra;
in
{
  # ───────────────────────────────────────────────────────────────────────────
  # Homelab: everything the Incus guests and the LAN services need.
  # ───────────────────────────────────────────────────────────────────────────
  options.flake.modules.nixos.homelabVars = mkOption {
    type = lib.types.deferredModule;
    default = _: {
      clan.core.vars.generators = {
        # ── Qdrant ──────────────────────────────────────────────────────────
        # Original recipe: `printf 'QDRANT_API_KEY=%s\n' "$(openssl rand -hex 32)"`
        # into a 0700 dir. Three readers: Qdrant, Bifrost, Gatus.
        qdrant-api-key =
          noDefault "qdrant-api-key" [
            "incus exec qdrant -- sh -c 'env | grep QDRANT__SERVICE__API_KEY'"
            "  | clan vars set homelab qdrant-api-key/api-key"
          ]
          // {
            files.api-key = secretFile { };
          };

        # ── Bifrost ─────────────────────────────────────────────────────────
        # Was one secrets.env with three keys, seeded by two different units
        # (postgres-secrets owned the DB password). Three generators now:
        # rotating the DB password cannot orphan the encryption key.
        #
        # Original recipes: hex24, hex32, hex32.
        bifrost-db-password =
          noDefault "bifrost-db-password" [
            "incus config show bifrost --expanded | grep BIFROST_POSTGRES_PASSWORD"
            "  | clan vars set homelab bifrost-db-password/db-password"
          ]
          // {
            files.db-password = secretFile { };
          };
        bifrost-encryption-key =
          noDefault "bifrost-encryption-key" [
            "incus config show bifrost --expanded | grep BIFROST_ENCRYPTION_KEY"
            "  | clan vars set homelab bifrost-encryption-key/encryption-key"
          ]
          // {
            files.encryption-key = secretFile { };
          };
        bifrost-setup-token =
          noDefault "bifrost-setup-token" [
            "incus config show bifrost --expanded | grep BIFROST_SETUP_TOKEN"
            "  | clan vars set homelab bifrost-setup-token/setup-token"
          ]
          // {
            files.setup-token = secretFile { };
          };

        # ── Reactive Resume ─────────────────────────────────────────────────
        # Postgres holds the matching role password; `postgres-secrets` applies
        # it with ALTER ROLE, which is why this must be adopted and not minted.
        # Original recipes: hex24 (RR_DB_PASSWORD), hex32 (AUTH_SECRET),
        # hex32 (ENCRYPTION_SECRET). AUTH_SECRET rotation invalidates every
        # session; ENCRYPTION_SECRET rotation makes stored fields unreadable.
        reactive-resume-db-password =
          noDefault "reactive-resume-db-password" [
            "incus exec reactive-resume -- sh -c 'echo $DATABASE_URL'  # password half"
            "  | clan vars set homelab reactive-resume-db-password/db-password"
          ]
          // {
            files.db-password = secretFile { };
          };
        reactive-resume-auth-secret =
          noDefault "reactive-resume-auth-secret" [
            "incus config show reactive-resume --expanded | grep AUTH_SECRET"
            "  | clan vars set homelab reactive-resume-auth-secret/auth-secret"
          ]
          // {
            files.auth-secret = secretFile { };
          };
        reactive-resume-encryption-secret =
          noDefault "reactive-resume-encryption-secret" [
            "incus config show reactive-resume --expanded | grep ENCRYPTION_SECRET"
            "  | clan vars set homelab reactive-resume-encryption-secret/encryption-secret"
          ]
          // {
            files.encryption-secret = secretFile { };
          };

        # ── SearXNG ─────────────────────────────────────────────────────────
        # Original recipe: `printf 'SEARX_SECRET_KEY=%s\n' "$(openssl rand -hex 32)"`.
        # Read by services.searx through environmentFile, so the `KEY=` prefix is
        # load-bearing. Rotation only invalidates existing CSRF tokens.
        searx-secret =
          noDefault "searx-secret" [
            "ssh surya@homelab.home.arpa 'sudo cat /var/lib/searx/secret.env'"
            "  | clan vars set homelab searx-secret/secret-env"
          ]
          // {
            files.secret-env = secretFile { };
          };

        # ── Nutify ──────────────────────────────────────────────────────────
        # Original recipe: `SECRET_KEY=$(openssl rand -hex 32)`. The container
        # validates its env before the web app starts, so the value must be
        # present from the first boot.
        nutify-secret =
          noDefault "nutify-secret" [
            "incus config show nutify --expanded | grep environment.SECRET_KEY"
            "  | clan vars set homelab nutify-secret/secret-env"
          ]
          // {
            files.secret-env = secretFile { };
          };

        # ── Booklore ────────────────────────────────────────────────────────
        # Two credentials, two containers: DB_PASSWORD is the app's MariaDB
        # login, MYSQL_ROOT_PASSWORD the server's. Kept separate precisely so a
        # rotation of one cannot silently break the other (the old single .env
        # made them look interchangeable). Original recipes: hex16, hex24.
        # MariaDB only reads MYSQL_ROOT_PASSWORD at first init, so adopting the
        # live value matters — a minted one would be ignored.
        booklore-db-password =
          noDefault "booklore-db-password" [
            "incus config show booklore --expanded | grep environment.DATABASE_PASSWORD"
            "  | clan vars set homelab booklore-db-password/db-password"
          ]
          // {
            files.db-password = secretFile { };
          };
        booklore-mysql-root-password =
          noDefault "booklore-mysql-root-password" [
            "incus config show booklore-db --expanded | grep MYSQL_ROOT_PASSWORD"
            "  | clan vars set homelab booklore-mysql-root-password/mysql-root-password"
          ]
          // {
            files.mysql-root-password = secretFile { };
          };

        # ── Hermes ──────────────────────────────────────────────────────────
        # Three host-side env files appended into the container's ~/.hermes/.env.
        # ~/.hermes/.env stays authoritative: the provisioning unit appends a
        # var only when the container lacks that key, so a migrated value wins.
        #
        # Original recipes: username surya + hex12 password + hex24 secret;
        # ENABLED/HOST/PORT constants + hex32 key.
        hermes-dashboard =
          noDefault "hermes-dashboard" [
            "incus exec hermes -- sudo -u hermes -- sh -c 'grep HERMES_DASHBOARD ~/.hermes/.env'"
            "  | clan vars set homelab hermes-dashboard/dashboard-env"
          ]
          // {
            files.dashboard-env = secretFile { };
          };
        hermes-api-server =
          noDefault "hermes-api-server" [
            "incus exec hermes -- sudo -u hermes -- sh -c 'grep API_SERVER ~/.hermes/.env'"
            "  | clan vars set homelab hermes-api-server/api-server-env"
          ]
          // {
            files.api-server-env = secretFile { };
          };
        # The Bifrost virtual key is *derived* from the container's
        # ~/.hermes/.env — a freshly minted key exists in no Bifrost
        # virtual-key record, so every gateway call 401s. That incident is why
        # modules/services/hermes.nix still reads .env first and only falls
        # back to this var; the var exists so the value has one home.
        hermes-bifrost-key =
          noDefault "hermes-bifrost-key" [
            "incus exec hermes -- sudo -u hermes -- grep BIFROST_API_KEY ~/.hermes/.env"
            "  | clan vars set homelab hermes-bifrost-key/bifrost-vk-env"
          ]
          // {
            files.bifrost-vk-env = secretFile { };
          };

        # ── grok-oauth-proxy ─────────────────────────────────────────────────
        # ADMIN_API_KEY is what Caddy injects on /grok, GROK_ADMIN_KEY is what
        # Gatus sends (same value by construction, which is why they share one
        # generator), GROK_CLIENT_KEY is the throwaway gate credential Bifrost
        # carries. Original recipe: hex24, hex24 (shared), hex24.
        grok-oauth =
          noDefault "grok-oauth" [
            "ssh surya@homelab.home.arpa 'sudo cat /var/lib/grok-oauth-proxy/secrets.env'"
            "  | clan vars set homelab grok-oauth/secrets-env"
          ]
          // {
            files.secrets-env = secretFile {
              # The proxy runs as grok-oauth-proxy with ProtectSystem=strict, so
              # the file has to be readable by that user, exactly as before.
              owner = "grok-oauth-proxy";
              group = "grok-oauth-proxy";
            };
          };

        # ── Homepage ─────────────────────────────────────────────────────────
        # The only human-supplied secret: AdGuard / Home Assistant / Nextcloud /
        # Booklore widget logins. `secrets` is a persisted prompt — answering it
        # once replaces the old "edit the file, then restart the dashboard"
        # workflow. `secrets-env` is the file the dashboard actually reads, so
        # the two cannot drift.
        #
        # Mode 0644: Homepage runs as a DynamicUser with no stable uid, and the
        # old file was deliberately world-readable for the same reason. The
        # values are LAN-service logins, not fleet credentials.
        homepage-vars = {
          files.secrets = {
            neededFor = "services";
            mode = "0400";
          };
          files.secrets-env = secretFile {
            mode = "0644";
          };
          prompts.secrets = {
            persist = true;
            type = "multiline-hidden";
            description = ''
              Homepage widget credentials, verbatim from the live
              /var/lib/homepage-dashboard-env/secrets.env (the HOMEPAGE_VAR_* lines).
            '';
          };
          script = ''
            umask 077
            if [ ! -s "$prompts/secrets" ]; then
              echo "homepage-vars/secrets was left empty; adopt the live file:" >&2
              echo "  clan vars set homelab homepage-vars/secrets < /var/lib/homepage-dashboard-env/secrets.env" >&2
              exit 1
            fi
            install -m 0644 "$prompts/secrets" "$out/secrets-env"
          '';
        };
      };
    };
  };

  # ───────────────────────────────────────────────────────────────────────────
  # Restic server (the pi): one htpasswd, one operator-readable client list.
  # ───────────────────────────────────────────────────────────────────────────
  options.flake.modules.nixos.resticServerVars = mkOption {
    type = lib.types.deferredModule;
    default = _: {
      clan.core.vars.generators.restic-htpasswd = {
        # Two files because they have different readers: rest-server reads the
        # bcrypt hash, the operator reads the plaintext copy to provision a
        # client. Original recipe: 24 alphanumerics per user, bcrypt, one line
        # per client, for the hosts that back up here (nixos, homelab).
        #
        # Adopted, never generated: this is the *auth* half of a relationship
        # whose other half is each client's restic-client/env. A minted hash
        # invalidates every client and the next nightly push 401s into an
        # unreadable repo.
        files.htpasswd = secretFile { };
        files.clients-env = secretFile { };
        inherit
          (noDefault "restic-htpasswd" [
            "ssh root@192.168.0.105 'cat /var/lib/restic-rest/htpasswd'"
            "  | clan vars set raspberry-pi restic-htpasswd/htpasswd"
            "ssh root@192.168.0.105 'cat /var/lib/restic-rest/clients.env'"
            "  | clan vars set raspberry-pi restic-htpasswd/clients-env"
          ])
          script
          ;
      };
    };
  };

  # ───────────────────────────────────────────────────────────────────────────
  # Restic client: the same shape on every host that pushes to the pi.
  # ───────────────────────────────────────────────────────────────────────────
  options.flake.modules.nixos.resticClientVars = mkOption {
    type = lib.types.deferredModule;
    default = _: {
      clan.core.vars.generators.restic-client = {
        files.env = secretFile { };
        inherit
          (noDefault "restic-client" [
            "ssh root@192.168.0.105 'cat /var/lib/restic-rest/clients.env'"
            "  # take this host's RESTIC_REST_<HOST>_USERNAME/PASSWORD lines, plus"
            "  # RESTIC_PASSWORD (the repository password, same on every client)"
            "  | clan vars set <machine> restic-client/env"
          ])
          script
          ;
      };
    };
  };
}
