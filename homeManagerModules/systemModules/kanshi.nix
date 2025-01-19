{ pkgs, ... }:
{
  services.kanshi = {
    enable = true;

    settings = [
      {
        profile.name = "laptop";
        profile.outputs = [
          { criteria = "eDP-1"; status = "enable"; }
        ];
        profile.exec = "hyprctl keyword monitor eDP-1,preferred,auto,1";
      }
      {
        profile.name = "external";
        profile.outputs = [
          { criteria = "eDP-1"; status = "disable"; }
          { criteria = "DP-1"; status = "enable"; }
        ];
      }
    ];
  };

}
