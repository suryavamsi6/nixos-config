# Auto-imports all host definitions
{ ... }:
{
  imports = [
    ./nixos-hyprland.nix
    ./nixos-gnome.nix
    ./nixos-raspberry-pi.nix
    ./darwin-macbook-air.nix
  ];
}
