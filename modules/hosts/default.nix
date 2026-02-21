# Auto-imports all host definitions
{ ... }:
{
  imports = [
    ./nixos-hyprland.nix
    ./nixos-gnome.nix
    ./darwin-macbook-air.nix
  ];
}
