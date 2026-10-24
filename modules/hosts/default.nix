# Auto-imports all host definitions
{ ... }:
{
  imports = [
    ./nixos-hyprland.nix
    ./nixos-mango.nix
    ./nixos-raspberry-pi.nix
    ./nixos-homelab.nix
    ./darwin-macbook-air.nix
  ];
}
