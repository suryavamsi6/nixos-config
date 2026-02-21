# GNOME desktop (NixOS)
{ lib, ... }:
{
  options.flake.modules.nixos.gnome = lib.mkOption {
    type = lib.types.deferredModule;
    default = { ... }: {
      services.desktopManager.gnome.enable = true;
    };
  };
}
