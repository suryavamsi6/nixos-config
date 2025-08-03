{ pkgs, inputs, ... }:
{
  environment.systemPackages = with pkgs; [
    polychromatic
    pavucontrol
    openrgb
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
    glance
    floorp
    sbctl
    niv
    inputs.quickshell.packages."${system}".default
  ];

  services.upower.enable = true;

  hardware.openrazer.enable = false;
  qt.enable = true;
  programs.nh = {
    enable = true;
    flake = "/home/$USER/Dotfiles/nixos-config";
  };
}
