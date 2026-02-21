# User accounts (NixOS + Darwin)
{ lib, ... }:
{
  options.flake.modules.nixos.users = lib.mkOption {
    type = lib.types.deferredModule;
    default = { ... }: {
      users.users.surya = {
        isNormalUser = true;
        description = "Surya Vamsi";
        extraGroups = [
          "networkmanager"
          "wheel"
          "openrazer"
          "disk"
        ];
        packages = [ ];
      };
    };
  };

  # Gnome host has slightly fewer groups, but we use the superset.
  # The hyprland host adds "disk" which is harmless on gnome too.

  options.flake.modules.darwin.users = lib.mkOption {
    type = lib.types.deferredModule;
    default = { ... }: {
      system.primaryUser = "suryavamsi";
    };
  };
}
