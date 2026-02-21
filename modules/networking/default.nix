# Networking — NetworkManager, samba (NixOS)
{ lib, ... }:
{
  options.flake.modules.nixos.networking = lib.mkOption {
    type = lib.types.deferredModule;
    default = { ... }: {
      networking.networkmanager.enable = true;
    };
  };

  # Samba is only for the hyprland host, so it's a separate option
  options.flake.modules.nixos.samba = lib.mkOption {
    type = lib.types.deferredModule;
    default = { ... }: {
      services.samba = {
        enable = true;
        settings = {
          global.security = "user";
          "pibackups" = {
            path = "/home/surya/Backup_Pi";
            browseable = "yes";
            "read only" = "no";
            "guest ok" = "no";
            "valid users" = "surya";
            "create mask" = "0664";
            "directory mask" = "0775";
          };
        };
        openFirewall = true;
      };
      services.samba-wsdd.enable = true;
    };
  };
}
