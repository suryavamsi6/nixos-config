{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    polychromatic
    overskride
    pavucontrol
    mcontrolcenter
    superfile
    toybox
  ];

  hardware.openrazer.enable = true;

  programs.nh = {
    enable = true;
    flake = "/home/$USER/Dotfiles/nixos-config";
  };
}
