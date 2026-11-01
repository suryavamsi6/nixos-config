# Bifrost: the open-source AI gateway, in an Incus OCI container.
#
# Extracted from modules/hosts/nixos-homelab.nix (§7 item 8.2 of
# plans/clan-deploy-rs-migration.md).
#
# Postgres holds its config and logs, so there is no SQLite volume. The image is
# pinned to the v2.3.2 index digest; do not float it to latest. LiteLLM used to
# own this role and is fully gone — no unit, no container, no DB, no Caddy
# vhost, no firewall port. The `providers.litellm` entry in the config below is
# only the Hermes cleanup list; do not re-add it as a live provider.
#
# It also exposes an MCP gateway (POST/GET /mcp, SSE) with upstreams added at
# /mcp-clients. mcp.home.arpa points at MCPHub, so this gateway is reachable
# only through bifrost.home.arpa. STDIO upstreams would need their binary inside
# this minimal image, which it does not have.
#
# config.json is authoritative: the unit renders it and pushes it into the
# container, then restarts Bifrost only when the file actually changed. Plugins
# edited in the UI are reverted from this file on the next switch — edit here.
# Provider keys and virtual keys are added in the UI, not here.
#
# First visit needs the setup token, read it on the host:
#   sudo sed -n 's/^BIFROST_SETUP_TOKEN=//p' /var/lib/bifrost/secrets.env
#
# LIVE DATA: guest address 10.110.0.100 and the /var/lib/bifrost state directory
# are wired into Caddy, Hermes and Postgres; do not move them.
{ lib, ... }:
{
  options.flake.modules.nixos.bifrost = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { config, pkgs, ... }:
      let
        # Three separate vars instead of one /var/lib/bifrost/secrets.env: the
        # DB password, the config-encryption key and the setup token have
        # different rotation hazards (rotating the encryption key orphans every
        # secret Bifrost has stored), so they no longer share a file or a unit.
        vars = config.clan.core.vars.generators;
        dbPasswordFile = vars.bifrost-db-password.files.db-password.path;
        encryptionKeyFile = vars.bifrost-encryption-key.files.encryption-key.path;
        setupTokenFile = vars.bifrost-setup-token.files.setup-token.path;
        apiKeyFile = vars.qdrant-api-key.files.api-key.path;
      in
      {
        systemd.services.incus-bifrost = {
          description = "Provision Bifrost gateway container";
          wantedBy = [ "multi-user.target" ];
          after = [
            "incus.service"
            "network-online.target"
            "postgres-secrets.service"
            "postgresql.service"
            "incus-qdrant.service"
          ];
          wants = [
            "network-online.target"
            "incus-qdrant.service"
          ];
          requires = [
            "incus.service"
            "postgres-secrets.service"
            "qdrant-secrets.service"
          ];
          serviceConfig = {
            Type = "simple";
            Restart = "on-failure";
            RestartSec = "15s";
          };
          path = [
            pkgs.incus
            pkgs.gnugrep
            pkgs.gnused
            pkgs.coreutils
            pkgs.diffutils
          ];
          script = ''
            set -euo pipefail
            incus remote list --format csv | cut -d, -f1 | grep -qx docker ||
              incus remote add docker https://docker.io --protocol=oci

            dbpass=$(sed -n 's|^BIFROST_DB_PASSWORD=\(.*\)|\1|p' ${dbPasswordFile})
            enc=$(sed -n 's|^BIFROST_ENCRYPTION_KEY=\(.*\)|\1|p' ${encryptionKeyFile})
            setup=$(sed -n 's|^BIFROST_SETUP_TOKEN=\(.*\)|\1|p' ${setupTokenFile})
            qk=$(sed -n 's|^QDRANT_API_KEY=\(.*\)|\1|p' ${apiKeyFile})
            if [ -z "$dbpass" ] || [ -z "$enc" ] || [ -z "$setup" ]; then
              echo "bifrost Clan vars did not decrypt; is /run/secrets mounted?" >&2
              exit 1
            fi
            if [ -z "$qk" ]; then
              echo "qdrant api key is missing; qdrant-secrets should have seeded it" >&2
              exit 1
            fi
            # Bifrost's image is not guaranteed to ship curl/wget, so the
            # container is judged by Incus state and by its own log, never
            # by an HTTP probe from inside the unit.

            # Public base URL Bifrost registers as the OAuth redirect_uri when
            # it acts as a CLIENT to an upstream MCP server (Fold, Notion...).
            # Providers lock the redirect_uri at Dynamic Client Registration
            # time and reject cleartext http UNLESS the host is loopback (RFC
            # 8252 native-app flow) -- verified live: Fold's /oauth/register
            # returns 201 for http://127.0.0.1:8080/api/oauth/callback and 400
            # for http://bifrost.home.arpa/api/oauth/callback.
            # Loopback therefore needs no TLS origin, no CA to import and no
            # tailnet membership. The browser half is reached by tunnelling
            # this port from whatever machine runs it:
            #   ssh -N -L 8080:10.110.0.100:8080 surya@homelab.home.arpa
            # 8080 is what Bifrost's own docs call out as the loopback default.
            # The registered path is <this URL>/api/oauth/callback. Changing it
            # after a client authorized breaks that client ("Invalid redirect
            # URI"): delete and re-create the MCP client so DCR runs again.
            #
            # NOTE (2026-10-27): Fold (mcp.fold.money) still cannot complete
            # this flow. Captured at the callback: Fold returns
            #   error=invalid_request, "Clients must use code_challenge_method
            #   =S256, plain is not allowed"
            # and mangles the opaque state (inserts a '+' into a 32-char
            # base64url value): Ph-tZG0q... arrives as Ph-tZ+G0q.... Both are
            # Fold-side bugs; Bifrost's authorize URL is well formed and its
            # DCR registration was accepted. Fold's OAuth is tested against
            # Claude/ChatGPT/Cursor only. The loopback base below is still
            # correct for any other OAuth MCP server.
            mcpPublicUrl=http://127.0.0.1:8080

            # v2.3.2 manifest list (2026-10-20); MCP gateway needs >= v1.4.0.
            # The ref MUST use the remote alias `docker:` — Incus splits
            # remote from image at the FIRST colon, so `docker.io/...@sha256:`
            # parsed `docker.io/maximhq/bifrost@sha256` as a remote name and
            # crashed this unit in a loop ("The remote ... doesn't exist").
            # The remote is per-user client config: root has it (added here),
            # other users must `incus remote add docker https://docker.io
            # --protocol=oci` themselves before any manual container work.
            image=docker:maximhq/bifrost@sha256:f5b18826349fe9e1c402c10d19f1cbb5567a3c800ad928580d07f72e69106ec7
            if ! incus list --format csv -c n | grep -qx bifrost; then
              incus init "$image" bifrost \
                -c boot.autostart=true \
                -c limits.memory=1GiB \
                -c limits.cpu=1 \
                -c security.nesting=true
              incus config device set bifrost eth0 ipv4.address=10.110.0.100 ||
                incus config device override bifrost eth0 ipv4.address=10.110.0.100
            fi

            incus config set bifrost \
              environment.APP_HOST=0.0.0.0 \
              environment.APP_PORT=8080 \
              environment.APP_DIR=/app/data \
              environment.LOG_LEVEL=info \
              environment.LOG_STYLE=json \
              environment.BIFROST_EXTERNAL_URL=http://bifrost.home.arpa \
              environment.BIFROST_ENCRYPTION_KEY="$enc" \
              environment.BIFROST_SETUP_TOKEN="$setup" \
              environment.BIFROST_CONFIG_STORE_TYPE=postgres \
              environment.BIFROST_LOGS_STORE_TYPE=postgres \
              environment.BIFROST_POSTGRES_HOST=10.110.0.1 \
              environment.BIFROST_POSTGRES_PORT=5432 \
              environment.BIFROST_POSTGRES_USER=bifrost \
              environment.BIFROST_POSTGRES_PASSWORD="$dbpass" \
              environment.BIFROST_POSTGRES_DATABASE=bifrost \
              environment.BIFROST_POSTGRES_SSLMODE=disable \
              environment.BIFROST_OAUTH_REDIRECT_URL="$mcpPublicUrl" \
              environment.QDRANT_HOST=10.110.0.102 \
              environment.QDRANT_API_KEY="$qk"

            state=$(incus list bifrost --format csv -c s)
            if [ "$state" != RUNNING ]; then
              incus start bifrost
            fi

            # The OAuth client redirect base, the vector store and the cache
            # plugin cannot be set through POST/PUT /api/config: the API
            # rejects the env-reference form ("mcp_external_client_url must be
            # an absolute HTTP or HTTPS URL") and silently drops the
            # {"type":"env"} object form. So all three are seeded from
            # config.json, which Bifrost reconciles into its config store at
            # startup. Reconciliation only runs when the file content hash
            # changes, so a UI edit to a referenced *value* survives normal
            # restarts; editing this file is what resets those sections (that
            # is why log_retention_days is pinned explicitly -- a partial
            # `client` section zeroed it to 0 on the first reconcile).
            #
            # source_of_truth stays at the default `split`: file-backed
            # sections are re-applied only when their hash changes, so UI
            # edits elsewhere (providers, virtual keys) are never pruned by
            # this unit. `plugins` is the exception: see below.
            #
            # CACHING (`plugins.semantic_cache`, labelled "Local Cache" in the
            # UI) runs in "direct" (hash) mode: dimension 1 and no
            # provider/embedding_model. Semantic mode would need an
            # embedding model; openrouter does expose
            # `openai/text-embedding-3-small` (1536) and Bifrost gained
            # OpenRouter embedding support, so it is reachable -- but its
            # per-key `models` allowlist (owned by the DB, not this file) has
            # to include that id first, and a failed embed on every direct
            # miss would add latency to live traffic. Turn it on in the UI
            # (Settings -> Caching -> Direct + Semantic) once that key lists
            # it, and let the UI pick a NEW vector_store_namespace: an
            # existing Qdrant collection keeps its original dimension and
            # startup fails on the mismatch.
            #
            #   ttl accepts a duration string OR seconds (300 = 5m).
            #   conversation_history_threshold 3 caches only requests with
            #   <=3 messages, which keeps long agent loops (pi, crush,
            #   hermes) from replaying stale tool-driven answers.
            #   default_cache_key is what makes caching engage at all:
            #   Bifrost only caches requests carrying x-bf-cache-key and no
            #   client here sends that header. Entries stay scoped by
            #   virtual key + user (disable_identity_scoping false), so one
            #   tenant's answer is never replayed to another.
            #
            # FEATURE FLAGS (`feature_flags.flags`) -- object keyed by flag
            # name; a flag set here is locked in the UI. `warp` is the
            # dashboard agent and its flag is only the master switch: while
            # it is off every /api/warp route 404s. It needs the vector
            # store above (present), a logs store (postgres, present) and
            # its own model + embedding provider, which are DB-only and set
            # in Settings -> Warp. Expect the flag on with the panel still
            # asking for a model until that is done.
            #
            # NOTE: plugins edited in the UI are reverted from config.json on
            # restart under split mode (maximhq/bifrost#6434). Tuning the
            # cache in the UI is therefore temporary -- either change it
            # here or move source_of_truth to `database` on purpose.
            # /run, not /tmp: /tmp is sticky world-writable and
            # fs.protected_regular makes root's `cat >` fail with EACCES when
            # the target already exists and belongs to another user (exactly
            # what happened here -- a hand-run test left a surya-owned file).
            install -d -m 0755 /run/bifrost
            cfg=/run/bifrost/config.json
            cat > "$cfg" <<'BIFROST_CONFIG'
            {
              "client": {
                "mcp_external_client_url": "env.BIFROST_OAUTH_REDIRECT_URL",
                "log_retention_days": 365
              },
              "vector_store": {
                "enabled": true,
                "type": "qdrant",
                "config": {
                  "host": "env.QDRANT_HOST",
                  "port": 6334,
                  "api_key": "env.QDRANT_API_KEY",
                  "use_tls": false
                }
              },
              "plugins": [
                {
                  "name": "semantic_cache",
                  "enabled": true,
                  "config": {
                    "dimension": 1,
                    "ttl": 300,
                    "threshold": 0.8,
                    "conversation_history_threshold": 3,
                    "cache_by_model": true,
                    "cache_by_provider": true,
                    "vector_store_namespace": "BifrostSemanticCachePlugin",
                    "default_cache_key": "bifrost-default",
                    "cache_tool_call_responses": false,
                    "disable_identity_scoping": false
                  }
                }
              ],
              "feature_flags": {
                "flags": {
                  "warp": {
                    "enabled": true
                  }
                }
              }
            }
            BIFROST_CONFIG
            incus file pull bifrost/app/data/config.json /run/bifrost/config.current >/dev/null 2>&1 ||
              : > /run/bifrost/config.current
            if ! cmp -s "$cfg" /run/bifrost/config.current; then
              incus file push "$cfg" bifrost/app/data/config.json
              echo "bifrost config.json updated; restarting to reconcile" >&2
              incus restart bifrost
            fi
          '';
        };
      };
  };
}
