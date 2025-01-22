{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    polychromatic
    overskride
    pavucontrol
    mcontrolcenter
    superfile
    toybox
    cosmic-files
    badwolf
    lm_sensors
  ];

  services.upower.enable = true;

  hardware.openrazer.enable = false;

  programs.nh = {
    enable = true;
    flake = "/home/$USER/Dotfiles/nixos-config";
  };
}
