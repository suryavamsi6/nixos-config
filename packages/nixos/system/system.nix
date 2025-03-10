{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    polychromatic
    pavucontrol
    mcontrolcenter
    superfile
    toybox
    cosmic-files
    librewolf
    lm_sensors
    p7zip
    unzip
    blueman
    cheese
    cameractrls-gtk4
  ];

  services.upower.enable = true;

  hardware.openrazer.enable = true;

  programs.nh = {
    enable = true;
    flake = "/home/$USER/Dotfiles/nixos-config";
  };
}
