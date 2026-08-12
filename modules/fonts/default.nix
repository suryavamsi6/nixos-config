# Font packages (NixOS + Darwin)
{ lib, ... }:
{
  options.flake.modules.nixos.fonts = lib.mkOption {
    type = lib.types.deferredModule;
    default = { pkgs, ... }: {
      fonts.packages = with pkgs; [
        inter
        nerd-fonts.fira-code
        nerd-fonts.caskaydia-cove
        nerd-fonts.jetbrains-mono
      ];
    };
  };

  options.flake.modules.darwin.fonts = lib.mkOption {
    type = lib.types.deferredModule;
    default = { pkgs, ... }: {
      fonts.packages = with pkgs; [
        nerd-fonts.jetbrains-mono
      ];
    };
  };
}
