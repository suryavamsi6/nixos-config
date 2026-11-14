# Audio — PipeWire (NixOS) + EasyEffects (home-manager)
{ lib, ... }:
{
  options.flake.modules.nixos.audio = lib.mkOption {
    type = lib.types.deferredModule;
    default = { pkgs, ... }: {
      security.rtkit.enable = true;

      # EasyEffects stores its settings through GSettings/KConfig; the
      # daemon needs the dconf service at runtime.
      programs.dconf.enable = true;

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

      # The ACCENTUM Plus stays A2DP-only: the PD200X is this machine's
      # microphone, and WirePlumber registers no HFP/HSP endpoints for the
      # headset (see bluez5.roles below), so playback never drops to the
      # headset codec.
      #
      # The battery plugin used to be excluded here (`-P battery`) because its
      # GATT notifications were suspected of destabilising the headset. That
      # flag also removes org.bluez.Battery1 entirely, so no battery level was
      # readable anywhere — which is why the bar and network popup lost the
      # percentage. bluetoothd now runs with its default plugin set; revisit
      # this if the headset starts dropping A2DP again.

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

        # Keep the ACCENTUM Plus on aptX HD permanently; the PD200X handles
        # all capture, so the headset never needs to leave A2DP.
        # Skip LE Audio (BAP) — it reconnect-loops on this chip. Games request
        # Pulse quantum 32 against a 44.1 kHz HD sink while the graph is locked
        # to 48 kHz, so allow 44.1 kHz and pin the Bluetooth node quantum.
        extraConfig.pipewire."51-clock-rates" = {
          "context.properties" = {
            "default.clock.allowed-rates" = [
              44100
              48000
            ];
          };
        };
        wireplumber.extraConfig."51-bluez-headset" = {
          "wireplumber.settings" = {
            # A2DP-only: never flip the headset to a capture profile.
            "bluetooth.autoswitch-to-headset-profile" = false;
            # WirePlumber's saved state still carries HFP profiles from the
            # autoswitch era; do not restore them onto a card that no longer
            # registers HFP endpoints.
            "bluetooth.use-persistent-storage" = false;
          };
          "monitor.bluez.properties" = {
            "bluez5.enable-sbc-xq" = true;
            "bluez5.enable-hw-volume" = true;
            # A2DP playback only. No hfp/hsp roles are registered, so the
            # headset exposes no microphone and the codec never changes;
            # capture is the PD200X's job.
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
                  # Connect playback only; no HFP endpoints exist to race it.
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

        # MAONO PD200X (usb 352f:0104). Pin it as the default source so
        # recording apps stop falling back to the webcam, and keep its
        # ALSA node resumed: a USB mic that suspends clips the first
        # syllable after idle. The node name embeds the unit's USB serial;
        # update it if the mic is replaced.
        wireplumber.extraConfig."51-pd200x-mic" = {
          "wireplumber.settings" = {
            "default.configured.audio.source" =
              "alsa_input.usb-352f_PD200X_Podcast_Microphone_214b206000000178-00.mono-fallback";
          };
          "monitor.alsa.rules" = [
            {
              matches = [ { "node.name" = "~alsa_input.usb-352f_PD200X.*"; } ];
              actions = {
                update-props = {
                  "session.suspend-timeout-seconds" = 0;
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
