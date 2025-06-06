{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    polychromatic
    pavucontrol
    mcontrolcenter
    superfile
    toybox
    cosmic-files
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
  ];

  services.upower.enable = true;

  hardware.openrazer.enable = true;

  programs.nh = {
    enable = true;
    flake = "/home/$USER/Dotfiles/nixos-config";
  };
}
