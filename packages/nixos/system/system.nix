{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    polychromatic
    pavucontrol
    mcontrolcenter
    superfile
    toybox
    nautilus
    nautilus-open-any-terminal
    lm_sensors
    p7zip
    unzip
    blueman
    cheese
    cameractrls-gtk4
    nodejs
    jetbrains.idea-ultimate
    glance
    floorp
    rpi-imager
    sbctl
    niv
  ];

  services.upower.enable = true;

  hardware.openrazer.enable = false;

  programs.nh = {
    enable = true;
    flake = "/home/$USER/Dotfiles/nixos-config";
  };
}
