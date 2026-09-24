# Auto-imports all host definitions
{ ... }:
{
  imports = [
    ./nixos-hyprland.nix
    ./nixos-mango.nix
    ./nixos-raspberry-pi.nix
    ./darwin-macbook-air.nix
  ];
}
