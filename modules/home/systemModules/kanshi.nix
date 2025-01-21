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
      }
      {
        profile.name = "external";
        profile.outputs = [
          { criteria = "eDP-1"; status = "enable"; }
          { criteria = "DP-1"; status = "enable"; }
        ];
      }
    ];
  };

}
