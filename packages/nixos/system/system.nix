{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    mcontrolcenter
    polychromatic
    overskride
  ];

  hardware.openrazer.enable = true;

  programs.nh = {
    enable = true;
    flake = "/home/$USER/dotfiles/nixos/";
  };
}
