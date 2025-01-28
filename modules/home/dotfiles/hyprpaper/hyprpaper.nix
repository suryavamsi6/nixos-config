{ ... }:
{
  services.hyprpaper = {
    enable = true;
    settings = {
      preload = [ "~/.config/wallpapers/car.png" ];
      wallpaper = [ "~./config/wallpapers/car.png" ];
    };
  };
}
