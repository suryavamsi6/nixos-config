{ ... }:
{
  services.hyprpaper = {
    enable = true;
    settings = {
      preload = [
        "~/.config/wallpapers/the_valley.png"
      ];
      wallpaper = [ ", ~/.config/wallpapers/the_valley.png" ];
    };
  };
}
