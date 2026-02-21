# Auto-imports all subdirectory modules
{ ... }:
{
  imports = [
    ./hosts
    ./hardware
    ./shell
    ./hyprland
    ./desktop
    ./darwin
    ./networking
    ./nix-settings
    ./users
    ./packages
    ./fonts
    ./audio
    ./boot
    ./environment
  ];
}
