{ ... }:
{
  services.hyprpaper = {
    enable = true;
    settings = {
      preload = [
        "~/.config/wallpapers/IUBepkp.jpeg"
      ];
      wallpaper = [ ", ~/.config/wallpapers/IUBepkp.jpeg "];
    };
  };
}
