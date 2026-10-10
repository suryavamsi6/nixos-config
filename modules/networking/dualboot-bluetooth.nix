# Bluetooth pairing keys shared with the dual-boot Windows 11 install (NixOS)
#
# Why: a paired device stores one key per host address — a classic (BR/EDR)
# device keeps a single link key, an LE device keeps an LTK/IRK — and both
# operating systems present the *same* adapter address (a dual-boot machine has
# one Bluetooth controller). Only the OS that paired the device *last* owns the
# key the device accepts, so the other OS is asked to pair again. `dualboot-bt-import`
# copies the Windows side of every pairing into BlueZ, so both installations
# hold identical material.
#
# Workflow:
#   1. Pair (or re-pair) the device in Windows last, and confirm it works there.
#   2. Boot NixOS. `dualboot-bt-import.service` imports the keys before bluetoothd
#      starts, so the device connects without pairing.
#   3. For a device paired only in Windows, the keys plus a minimal info file are
#      created; for one already paired here, only the key fields are replaced and
#      a copy of the previous file is kept under /var/lib/dualboot-bluetooth/backups.
#
# After pairing something new in Windows you can also sync without rebooting:
#   sudo dualboot-bt-import          # --dry-run to preview, --list to inspect
#
# Direction is deliberate: Windows is the source of truth. The Windows registry
# hive is read offline (ACLs do not apply to a copied file), which needs no
# tooling, task or script on the Windows side. Re-pairing a *classic* device on
# Linux overwrites the key Windows holds, and the imported (now stale) key then
# fails with `br-connection-key-missing` — pair classic devices on Windows last.
# LE-only devices (the Xbox controller) are not affected by that ordering.
{ lib, ... }:
{
  options.flake.modules.nixos.bluetoothDualboot = lib.mkOption {
    type = lib.types.deferredModule;
    default = { pkgs, ... }:
      let
        btImport = pkgs.writeShellApplication {
          name = "dualboot-bt-import";
          runtimeInputs = [
            pkgs.python3
            pkgs.chntpw
            pkgs.systemd
          ];
          text = ''
            exec ${pkgs.python3}/bin/python3 ${./dualboot-bluetooth/dualboot-bt-import.py} "$@"
          '';
        };
      in
      {
        # Read-only window onto the Windows system volume (WD_BLACK SN850X, C:).
        # ntfs3 is the in-kernel driver, so a read-only mount needs no FUSE
        # helper and cannot write to the volume Windows may still consider
        # dirty. If Fast Startup ever leaves the volume in a state ntfs3
        # refuses ("volume is dirty" in dmesg), boot Windows once and shut it
        # down fully; alternatively switch this to ntfs-3g:
        #   boot.supportedFilesystems = [ "ntfs-3g" ]; fsType = "ntfs-3g";
        boot.kernelModules = [ "ntfs3" ];
        fileSystems."/mnt/windows" = {
          device = "/dev/disk/by-uuid/846800146800081E";
          fsType = "ntfs3";
          options = [
            "ro"
            "nosuid"
            "nodev"
            "noexec"
            "nofail"
            # Mount on first access only: nothing at boot depends on Windows
            # being reachable, and the NTFS driver never runs unless asked.
            "x-systemd.automount"
            "x-systemd.idle-timeout=300"
            "x-systemd.device-timeout=10"
          ];
        };

        environment.systemPackages = [ btImport ];

        # BlueZ reads a bond when the device is registered, so the keys have to
        # be in place before bluetoothd starts. Do not restart Bluetooth from
        # here: the unit runs first in exactly the transaction that starts it.
        systemd.services.dualboot-bt-import = {
          description = "Import Bluetooth pairing keys from the dual-boot Windows install";
          before = [ "bluetooth.service" ];
          wantedBy = [ "bluetooth.service" ];
          serviceConfig = {
            Type = "oneshot";
            TimeoutStartSec = 90;
            ExecStart = "${btImport}/bin/dualboot-bt-import --no-restart --missing-ok";
          };
        };
      };
  };
}
