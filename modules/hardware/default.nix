# Auto-imports all hardware modules
{ ... }:
{
  imports = [
    ./nvidia.nix
    ./hyprland-hw.nix
    ./gnome-hw.nix
  ];
}
