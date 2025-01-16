{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    polychromatic
    overskride
    pavucontrol
    mcontrolcenter
  ];

  hardware.openrazer.enable = true;

  programs.nh = {
    enable = true;
    flake = "/home/$USER/dotfiles/nixos/";
  };
}
