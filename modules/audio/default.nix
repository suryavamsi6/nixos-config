# Audio — PipeWire (NixOS)
{ lib, ... }:
{
  options.flake.modules.nixos.audio = lib.mkOption {
    type = lib.types.deferredModule;
    default = { pkgs, ... }: {
      security.rtkit.enable = true;

      # MediaTek MT7922 (btusb). Keep autosuspend off so A2DP does not
      # drop on idle.
      boot.extraModprobeConfig = lib.mkAfter ''
        options btusb enable_autosuspend=0
      '';

      # Powered=false rfkill-blocks MT7922. systemd-rfkill then restores
      # that block on the next boot and AutoEnable fails with 0x03.
      systemd.services.bluetooth.serviceConfig.ExecStartPre = [
        "-${pkgs.util-linux}/bin/rfkill unblock bluetooth"
      ];

      hardware.bluetooth.settings = {
        General = {
          Experimental = true;
          FastConnectable = true;
          DisablePlugins = "headset";
        };
        Policy = {
          AutoEnable = true;
          # A2DP sink + A2DP only — do not retry Hands-Free; that SDP poll
          # keeps a sleeping ACCENTUM Plus in Host-is-down and blocks A2DP.
          ReconnectUUIDs = "0000110b-0000-1000-8000-00805f9b34fb,0000110d-0000-1000-8000-00805f9b34fb";
        };
      };

      services.pipewire = {
        enable = true;
        alsa.enable = true;
        alsa.support32Bit = true;
        pulse.enable = true;

        # Citrix opens a capture stream on session start. HFP/headset
        # autoswitch tears down A2DP and drops Qualcomm headsets
        # (ACCENTUM Plus). A2DP only; use the webcam mic for calls.
        # Skip LE Audio (BAP) — it reconnect-loops on this chip.
        wireplumber.extraConfig."51-bluez-a2dp-prefer" = {
          "wireplumber.settings" = {
            "bluetooth.autoswitch-to-headset-profile" = false;
          };
          "monitor.bluez.properties" = {
            "bluez5.enable-sbc-xq" = true;
            "bluez5.enable-msbc" = true;
            "bluez5.enable-hw-volume" = true;
            "bluez5.roles" = [
              "a2dp_sink"
              "a2dp_source"
            ];
          };
          "monitor.bluez.rules" = [
            {
              matches = [ { "device.name" = "~bluez_card.*"; } ];
              actions = {
                update-props = {
                  "bluez5.auto-connect" = [ "a2dp_sink" ];
                  "bluez5.hw-volume" = [ "a2dp_sink" ];
                };
              };
            }
          ];
        };
      };

      # BlueZ tries A2DP at login before WirePlumber has registered
      # endpoints ("Protocol not available"). Retry once Pulse is up.
      systemd.user.services.bt-reconnect-audio = {
        description = "Reconnect Bluetooth audio after PipeWire is ready";
        after = [ "pipewire-pulse.service" "wireplumber.service" ];
        wantedBy = [ "pipewire-pulse.service" ];
        serviceConfig = {
          Type = "oneshot";
          TimeoutStartSec = "45s";
          TimeoutStopSec = "5s";
          ExecStart = pkgs.writeShellScript "bt-reconnect-audio" ''
            bus=${pkgs.systemd}/bin/busctl
            sleep 8
            adapter=$($bus --system --timeout=2 tree org.bluez --list 2>/dev/null | grep -E '^/org/bluez/hci[0-9]+$' | head -n1)
            [ -n "$adapter" ] || exit 0
            $bus --system --timeout=2 tree org.bluez --list 2>/dev/null | grep -E "^''${adapter}/dev_[^/]+$" | while read -r dev; do
              uuids=$($bus --system --timeout=2 get-property org.bluez "$dev" org.bluez.Device1 UUIDs 2>/dev/null || true)
              echo "$uuids" | grep -q 0000110b-0000-1000-8000-00805f9b34fb || continue
              for _try in 1 2 3 4 5; do
                if $bus --system --timeout=2 get-property org.bluez "$dev" org.bluez.Device1 Connected 2>/dev/null | grep -q true; then
                  break
                fi
                $bus --system --timeout=2 call org.bluez "$dev" org.bluez.Device1 Disconnect >/dev/null 2>&1 || true
                sleep 2
                $bus --system --timeout=2 call org.bluez "$dev" org.bluez.Device1 Connect >/dev/null 2>&1 || true
                sleep 4
              done
            done
          '';
        };
      };
    };
  };
}
