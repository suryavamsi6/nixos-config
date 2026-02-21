# Hyprpaper — wallpaper service (home-manager)
{ lib, ... }:
{
  options.flake.modules.homeManager.hyprpaper = lib.mkOption {
    type = lib.types.deferredModule;
    default = { ... }: {
      services.hyprpaper = {
        enable = true;
        settings = {
          preload = [
            "~/.config/wallpapers/IUBepkp.jpeg"
          ];
          wallpaper = [ ", ~/.config/wallpapers/IUBepkp.jpeg "];
        };
      };
    };
  };
}
