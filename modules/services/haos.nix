# Home Assistant OS as an Incus VM.
#
# Extracted from modules/hosts/nixos-homelab.nix (§7 item 8.7 of
# plans/clan-deploy-rs-migration.md). The image is downloaded at runtime ON the
# homelab by incus-haos-vm.service rather than fetched through Nix, so the 510 MB
# qcow2 never enters the build closure and is not copied over the LAN on every
# deploy. The pinned sha256 is what keeps that download trustworthy; incus image
# import also needs a metadata tarball next to the rootfs, rendered here.
#
# The VM keeps its disk under /var/lib/incus — that is the live Home Assistant
# install (config, database, add-ons). Do not recreate or relocate it casually;
# this unit is idempotent and only provisions when the container is absent.
{ lib, ... }:
{
  options.flake.modules.nixos.haos = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { pkgs, ... }:
      let
        haosVersion = "18.3";
        # Pinned sha256 (hex) of haos_ova-18.3.qcow2.xz. Downloaded at runtime ON
        # the homelab by incus-haos-vm.service (not via fetchurl) so the 510 MB
        # image never enters the build closure or gets copied over the LAN on
        # every deploy.
        haosSha256 = "fae6a728768cc10aff60d4820bfcd40d64cd77fab82c8bd92af13b3d9d414090";
        # incus image import requires a metadata tarball next to the rootfs.
        haosMetadata =
          pkgs.runCommand "haos-${haosVersion}-metadata"
            {
              nativeBuildInputs = [ pkgs.gnutar ];
            }
            ''
              mkdir -p $out
              cat > metadata.yaml <<EOF
              architecture: x86_64
              creation_date: 1761180000
              properties:
                description: Home Assistant OS ${haosVersion} (ova)
                os: Home Assistant
                release: ${haosVersion}
              EOF
              tar -cf $out/metadata.tar metadata.yaml
            '';
      in
      {
        # --- Home Assistant OS as an Incus VM (idempotent, runs once) ---
        systemd.services.incus-haos-vm = {
          description = "Provision Home Assistant OS ${haosVersion} Incus VM";
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
            pkgs.xz
            pkgs.incus
            pkgs.curl
            pkgs.coreutils
          ];
          script = ''
            set -euo pipefail
            vm=home-assistant
            if incus list --format csv -c n | grep -qx "$vm"; then
              echo "$vm already exists, nothing to do"
              exit 0
            fi

            # Download directly on this host (single stream from GitHub,
            # verified against the pinned hash) instead of pushing the
            # image through the build closure.
            url="https://github.com/home-assistant/operating-system/releases/download/${haosVersion}/haos_ova-${haosVersion}.qcow2.xz"
            archive=/var/lib/incus/haos_${haosVersion}.qcow2.xz
            img=/var/lib/incus/haos_${haosVersion}.qcow2
            if [ ! -f "$archive" ]; then
              curl -fL --retry 3 -o "$archive.tmp" "$url"
              echo "${haosSha256}  $archive.tmp" | sha256sum -c -
              mv "$archive.tmp" "$archive"
            fi

            xz -dc "$archive" > "$img"
            incus image import ${haosMetadata}/metadata.tar "$img" --alias "haos-${haosVersion}"

            # HAOS is not secure-boot signed; disable SB for this VM only.
            incus init --vm "haos-${haosVersion}" "$vm" \
              -c security.secureboot=false \
              -c limits.memory=3GiB \
              -c limits.cpu=2
            incus config device override "$vm" root size=32GiB
            # Stable VM IP (DHCP reservation). No host port-forward: the
            # LAN reaches HA at http://homeassistant.home.arpa, where Caddy
            # proxies to 10.110.0.10:80 over incusbr0. A `proxy` device
            # DNATs for the whole LAN regardless of the firewall, so one
            # here would publish :8123 to the WiFi again.
            incus config device set "$vm" eth0 ipv4.address=10.110.0.10 ||
              incus config device override "$vm" eth0 ipv4.address=10.110.0.10
            incus config set "$vm" boot.autostart=true
            incus start "$vm"

            rm -f "$img"
          '';
        };
      };
  };
}
