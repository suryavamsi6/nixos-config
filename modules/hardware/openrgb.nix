# OpenRGB — MSI X670E Mystic Light / ARGB / RAM. GUI talks to the SDK
# server; i2c is for DRAM and SMBus devices (HID Mystic Light is USB).
#
# JRAINBOW1/2 are the 5V ARGB headers. OpenRGB hides size-0 zones, so
# persist 12 LEDs each (one fan per header).
{ lib, ... }:
{
  options.flake.modules.nixos.openrgb = lib.mkOption {
    type = lib.types.deferredModule;
    default = { pkgs, ... }:
    {
      hardware.i2c.enable = true;
      users.users.surya.extraGroups = [ "i2c" ];

      services.hardware.openrgb = {
        enable = true;
        package = pkgs.openrgb-with-all-plugins;
        motherboard = "amd";
      };

      systemd.tmpfiles.rules = [
        "C+ /var/lib/OpenRGB/sizes.ors 0644 root root - ${./openrgb-sizes.ors}"
      ];
      # User tmpfiles rules also run for greetd, whose home is /var/empty.
      home-manager.users.surya.home.file.".config/OpenRGB/sizes.ors".source = ./openrgb-sizes.ors;
    };
  };
}
