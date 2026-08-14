# Font packages (NixOS + Darwin)
{ lib, ... }:
{
  options.flake.modules.nixos.fonts = lib.mkOption {
    type = lib.types.deferredModule;
    default = { pkgs, ... }: {
      fonts.packages = with pkgs; [
        inter
        material-symbols
        eb-garamond
        cm_unicode
        nerd-fonts.fira-code
        nerd-fonts.caskaydia-cove
        nerd-fonts.jetbrains-mono
        nerd-fonts.iosevka
        nerd-fonts.symbols-only
        jetbrains-mono
        udev-gothic-nf
        (google-fonts.override {
          fonts = [
            "Newsreader"
            "Manrope"
            "EBGaramond"
          ];
        })
      ];

      fonts.fontconfig.defaultFonts = {
        sansSerif = [ "Inter" ];
        serif = [ "EB Garamond" ];
        monospace = [ "JetBrainsMono Nerd Font" "JetBrains Mono" ];
      };
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
