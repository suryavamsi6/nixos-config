# Audio — PipeWire (NixOS)
{ lib, ... }:
{
  options.flake.modules.nixos.audio = lib.mkOption {
    type = lib.types.deferredModule;
    default = { ... }: {
      security.rtkit.enable = true;
      services.pipewire = {
        enable = true;
        alsa.enable = true;
        alsa.support32Bit = true;
        pulse.enable = true;

        # Bluetooth headsets: stay on A2DP (music quality) by default;
        # switch to HFP/headset only when an app opens the mic.
        wireplumber.extraConfig."51-bluez-a2dp-prefer" = {
          "wireplumber.settings" = {
            "bluetooth.autoswitch-to-headset-profile" = true;
          };
          "monitor.bluez.rules" = [
            {
              matches = [ { "device.name" = "~bluez_card.*"; } ];
              actions = {
                update-props = {
                  # Do not auto-connect HFP on link; A2DP only until mic is needed.
                  "bluez5.auto-connect" = [ "a2dp_sink" ];
                  "bluez5.hw-volume" = [
                    "a2dp_sink"
                    "hfp_hf"
                    "hsp_hs"
                  ];
                };
              };
            }
          ];
        };
      };
    };
  };
}
