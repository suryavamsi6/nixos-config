{ pkgs, ... }:
{
  services.kanshi = {
    enable = true;

    profiles = {
      undocked = {
        name = "undocked";
        outputs = [
          {
            criteria = "eDP-1";
            status = "enable";
          }
        ];
      };
      docked = {
        name = "docked";
        outputs = [
          {
            criteria = "eDP-1";
            status = "disable";
          }
          {
            criteria = "DP-1";
            status = "enable";
          }
        ];
      };
    };
  };
}
