# Wallpaper file declarations (home-manager)
{ lib, ... }:
{
  options.flake.modules.homeManager.wallpapers = lib.mkOption {
    type = lib.types.deferredModule;
    default = { ... }: {
      home.file.".config/wallpapers/leaf.png" = {
        source = ./wallpaper-assets/leaf.png;
      };

      home.file.".config/wallpapers/pfp.png" = {
        source = ./wallpaper-assets/pfp.png;
      };

      home.file.".config/wallpapers/nier.webp" = {
        source = ./wallpaper-assets/nier.webp;
      };

      home.file.".config/wallpapers/car.png" = {
        source = ./wallpaper-assets/car.png;
      };

      home.file.".config/wallpapers/IUBepkp.jpeg" = {
        source = ./wallpaper-assets/IUBepkp.jpeg;
      };
    };
  };
}
