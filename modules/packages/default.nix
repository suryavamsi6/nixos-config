# Auto-imports all package modules
{ ... }:
{
  imports = [
    ./dev.nix
    ./work.nix
    ./gaming.nix
    ./social.nix
    ./system.nix
  ];
}
