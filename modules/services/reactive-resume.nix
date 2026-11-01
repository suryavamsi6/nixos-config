# Reactive Resume v6 in an Incus OCI container.
#
# Extracted verbatim from modules/hosts/nixos-homelab.nix (§7 step 8 of
# plans/clan-deploy-rs-migration.md). The official image, not a nixpkgs module:
# v6 is one Node process serving the web app, the API and local uploads. PDFs
# render in the browser, so there is no printer container. Postgres is this
# host's own instance (role reactive_resume) reached at 10.110.0.1:5432; uploads
# live in a host directory owned by the image's node user (UID 1000).
#
# The tag is pinned to the v6.0.6 index digest so "latest" cannot move the host
# onto the next major; a newer patch release is a deliberate digest bump here,
# then a restart of this unit, which recreates the container (the data disk
# survives).
#
# Secrets come from postgres-secrets and never enter the flake; this unit reads
# them back from /var/lib/reactive-resume/secrets.env on every run and does not
# rotate them. UI: http://resume.home.arpa (Caddy). No host port is opened.
#
# Signups stay open until the first account exists. After that:
#   printf 'FLAG_DISABLE_SIGNUPS=true\n' | sudo tee /var/lib/reactive-resume/flags.env
#   sudo systemctl restart incus-reactive-resume
# The unit pushes the flag and restarts the container; it does not delete it.
{ lib, ... }:
{
  options.flake.modules.nixos.reactiveResume = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { pkgs, ... }:
      {
        systemd.services.incus-reactive-resume = {
          description = "Provision Reactive Resume Incus container";
          wantedBy = [ "multi-user.target" ];
          after = [
            "incus.service"
            "postgres-secrets.service"
            "network-online.target"
          ];
          wants = [ "network-online.target" ];
          requires = [
            "incus.service"
            "postgres-secrets.service"
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          path = [
            pkgs.incus
            pkgs.gnugrep
            pkgs.coreutils
            pkgs.gnused
          ];
          script = ''
            set -euo pipefail
            secrets=/var/lib/reactive-resume/secrets.env
            test -s "$secrets"
            dbpass=$(sed -n 's|^RR_DB_PASSWORD=\(.*\)|\1|p' "$secrets")
            auth=$(sed -n 's|^AUTH_SECRET=\(.*\)|\1|p' "$secrets")
            enc=$(sed -n 's|^ENCRYPTION_SECRET=\(.*\)|\1|p' "$secrets")
            test -n "$dbpass"
            test -n "$auth"
            test -n "$enc"

            # Optional second-account lock. Absent means signups stay
            # open, which is required for the first account.
            flags=/var/lib/reactive-resume/flags.env
            signups=false
            if [ -f "$flags" ] && grep -q '^FLAG_DISABLE_SIGNUPS=true$' "$flags"; then
              signups=true
            fi

            install -d -o 1000 -g 1000 -m 750 /var/lib/reactive-resume/data

            incus remote list --format csv | cut -d, -f1 | grep -qx ghcr ||
              incus remote add ghcr https://ghcr.io --protocol=oci

            # v6.0.6 index digest (2026-10-25). A newer patch release is a
            # deliberate digest bump here, then a restart of this unit,
            # which recreates the container. The data disk survives that.
            image=ghcr:reactive-resume/reactive-resume@sha256:9ba846665ec3b703c904f61ed75cc0e2c0fe71efd2fd51f45600c6ce23744e78
            if ! incus list --format csv -c n | grep -qx reactive-resume; then
              incus init "$image" reactive-resume \
                -c boot.autostart=true \
                -c limits.memory=1GiB \
                -c limits.cpu=1
              incus config device add reactive-resume data disk \
                source=/var/lib/reactive-resume/data path=/app/data shift=true
              incus config device set reactive-resume eth0 ipv4.address=10.110.0.80 ||
                incus config device override reactive-resume eth0 ipv4.address=10.110.0.80
            fi

            # OCI instances read these as process environment. A bind
            # mount of .env would not: the image does not load a file.
            set_env() {
              current=$(incus config get reactive-resume "environment.$1" || true)
              if [ "$current" != "$2" ]; then
                incus config set reactive-resume "environment.$1" "$2"
                changed=1
              fi
            }
            changed=0
            set_env APP_URL http://resume.home.arpa
            set_env DATABASE_URL "postgresql://reactive_resume:''${dbpass}@10.110.0.1:5432/reactive_resume"
            set_env AUTH_SECRET "$auth"
            set_env ENCRYPTION_SECRET "$enc"
            set_env STORAGE_BACKEND local
            set_env LOCAL_STORAGE_PATH /app/data
            set_env PORT 3000
            set_env FLAG_DISABLE_SIGNUPS "$signups"
            set_env FLAG_ALLOW_UNSAFE_AI_BASE_URL true
            # SearXNG listens on 127.0.0.1:8888 only, so the container
            # cannot open 10.110.0.1:8888. Caddy proxies search.home.arpa
            # to that loopback listener, and the container can resolve it.
            set_env WEB_SEARCH_SEARXNG_URL http://search.home.arpa

            state=$(incus list '^reactive-resume$' --format csv -c s)
            if [ "$state" != RUNNING ]; then
              incus start reactive-resume
            elif [ "$changed" = 1 ]; then
              incus restart reactive-resume
            fi
          '';
        };
      };
  };
}
