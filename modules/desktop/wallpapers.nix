# Wallpapers from ilyamiro/shell-wallpapers (Serpantinum companion set).
{ lib, ... }:
{
  options.flake.modules.homeManager.wallpapers = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { inputs, ... }:
      {
        home.file.".config/wallpapers/pfp.png".source = ./wallpaper-assets/pfp.png;
        home.file."Pictures/Wallpapers" = {
          source = "${inputs.shell-wallpapers}/images";
          recursive = true;
        };
      };
  };
}
