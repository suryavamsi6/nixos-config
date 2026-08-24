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

      # BlueZ 5.87 no longer accepts DisablePlugins in main.conf.  Pass the
      # exclusions on its command line instead: the battery plugin's GATT
      # notify request makes the ACCENTUM's LE bearer time out and can take
      # down its BR/EDR audio bearer with it.
      systemd.services.bluetooth.serviceConfig.ExecStart = lib.mkForce [
        ""
        "${pkgs.bluez}/libexec/bluetooth/bluetoothd -f /etc/bluetooth/main.conf -P headset,battery"
      ];

      hardware.bluetooth.settings = {
        General = {
          Experimental = true;
          FastConnectable = true;
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
        # Keep aptX HD. Games request Pulse quantum 32 against a 44.1 kHz
        # HD sink while the graph is locked to 48 kHz, so WirePlumber
        # underruns and kills the transport. Allow 44.1 kHz and pin the
        # Bluetooth node quantum; do not cap the codec.
        extraConfig.pipewire."51-clock-rates" = {
          "context.properties" = {
            "default.clock.allowed-rates" = [
              44100
              48000
            ];
          };
        };
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
            {
              matches = [ { "node.name" = "~bluez_output.*"; } ];
              actions = {
                update-props = {
                  "node.pause-on-idle" = false;
                  "session.suspend-timeout-seconds" = 0;
                  "pulse.min.req" = "1024/44100";
                  "pulse.min.quantum" = "1024/44100";
                };
              };
            }
          ];
        };
      };

      # BlueZ tries A2DP at login before WirePlumber has registered
      # endpoints ("Protocol not available").  Keep watching Device1
      # signals afterward: a lost A2DP transport can leave PipeWire's old
      # sink in error, while a normal one-shot startup retry cannot restore
      # it.  All state reads and reconnects use BlueZ D-Bus directly; do not
      # invoke bluetoothctl or scan from this service.
      systemd.user.services.bt-reconnect-audio = {
        description = "Recover Bluetooth audio after PipeWire is ready";
        after = [
          "pipewire-pulse.service"
          "wireplumber.service"
        ];
        wantedBy = [ "pipewire-pulse.service" ];
        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = "5s";
          TimeoutStopSec = "5s";
          ExecStart = pkgs.writeShellScript "bt-recover-audio" ''
            bus=${pkgs.systemd}/bin/busctl
            monitor=${pkgs.dbus}/bin/dbus-monitor
            sleep 8

            recover() {
              adapter=$($bus --system --timeout=2 tree org.bluez --list 2>/dev/null | grep -E '^/org/bluez/hci[0-9]+$' | head -n1)
              [ -n "$adapter" ] || return 0
              $bus --system --timeout=2 tree org.bluez --list 2>/dev/null | grep -E "^''${adapter}/dev_[^/]+$" | while read -r dev; do
                uuids=$($bus --system --timeout=2 get-property org.bluez "$dev" org.bluez.Device1 UUIDs 2>/dev/null || true)
                echo "$uuids" | grep -q 0000110b-0000-1000-8000-00805f9b34fb || continue
                $bus --system --timeout=2 get-property org.bluez "$dev" org.bluez.Device1 Connected 2>/dev/null | grep -q true && continue
                for _try in 1 2 3 4 5; do
                  $bus --system --timeout=2 call org.bluez "$dev" org.bluez.Device1 Disconnect >/dev/null 2>&1 || true
                  sleep 2
                  $bus --system --timeout=2 call org.bluez "$dev" org.bluez.Device1 Connect >/dev/null 2>&1 || true
                  sleep 4
                  $bus --system --timeout=2 get-property org.bluez "$dev" org.bluez.Device1 Connected 2>/dev/null | grep -q true && break
                done
              done
            }

            recover
            $monitor --system "type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',arg0='org.bluez.Device1'" 2>/dev/null |
              while read -r line; do
                case "$line" in
                  *"member=PropertiesChanged"*) recover ;;
                esac
              done
          '';
        };
      };
    };
  };
}
