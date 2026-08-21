# Auto-imports all hardware modules
{ ... }:
{
  imports = [
    ./nvidia.nix
    ./hyprland-hw.nix
    ./gcb200.nix
  ];
}
