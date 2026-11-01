# OpenBot agent server in an Ubuntu 24.04 Incus container.
#
# Extracted verbatim from modules/hosts/nixos-homelab.nix (§7 step 7 of
# plans/clan-deploy-rs-migration.md). It stays a systemd oneshot that provisions
# an Incus container rather than a nixpkgs module because the upstream installer
# is Ubuntu-only: it runs apt-get and an in-image setup script, so the whole
# install has to happen inside the guest.
#
# Idempotent: re-running the switch converges the existing container instead of
# recreating it. Finish the login by hand once, inside the guest:
#   sudo incus exec openbot -- sudo openbot login
# Agents are then reached through your OpenBot account (desktop/mobile app or
# openbot.run/app).
{ lib, ... }:
{
  options.flake.modules.nixos.openbot = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { pkgs, ... }:
      {
        systemd.services.incus-openbot = {
          description = "Provision OpenBot server Incus container";
          wantedBy = [ "multi-user.target" ];
          after = [
            "incus.service"
            "network-online.target"
          ];
          wants = [ "network-online.target" ];
          requires = [ "incus.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          path = [
            pkgs.incus
            pkgs.gnugrep
          ];
          script = ''
            set -euo pipefail
            exists=no
            if incus list --format csv -c n | grep -qx openbot; then
              exists=yes
            fi

            if [ "$exists" = no ]; then
              incus launch images:ubuntu/24.04 openbot \
                -c boot.autostart=true \
                -c limits.memory=2GiB \
                -c limits.cpu=1
              # Wait for container network + apt to be ready.
              sleep 15
              incus exec openbot -- cloud-init status --wait >/dev/null 2>&1 || true
              incus exec openbot -- bash -c \
                'curl -fsSL https://raw.githubusercontent.com/nightly-labs/openbot/main/scripts/install-server.sh | sudo bash -s -- --user openbot'
            fi

            # Reconcile caps and address on containers that predate
            # them; launch sets config only at creation (hermes
            # pattern). Memory raises apply live; the static address
            # lands on the container's next DHCP renew or reboot.
            if [ "$(incus config get openbot limits.memory)" != "2GiB" ]; then
              incus config set openbot limits.memory=2GiB
            fi
            if [ "$(incus config get openbot limits.cpu)" != "1" ]; then
              incus config set openbot limits.cpu=1
            fi
            # Static bridge address like the other instances (DHCP
            # .241 drifts). `device set` fails while eth0 exists only
            # in the profile, hence the override fallback (HAOS
            # pattern).
            incus config device set openbot eth0 ipv4.address=10.110.0.70 ||
              incus config device override openbot eth0 ipv4.address=10.110.0.70
          '';
        };
      };
  };
}
