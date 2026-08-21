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
          "disk"
        ];
        packages = [ ];
      };
    };
  };

  options.flake.modules.darwin.users = lib.mkOption {
    type = lib.types.deferredModule;
    default = { ... }: {
      system.primaryUser = "suryavamsi";
    };
  };
}
