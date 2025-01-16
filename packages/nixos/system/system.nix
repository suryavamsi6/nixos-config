{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    mcontrolcenter
    polychromatic
    overskride
    pavucontrol
  ];

  hardware.openrazer.enable = true;

  programs.nh = {
    enable = true;
    flake = "/home/$USER/dotfiles/nixos/";
  };
}
