# Auto-imports all desktop modules
{ ... }:
{
  imports = [
    ./serpantinum.nix
    ./wallpapers.nix
    ./greetd.nix
    ./gnome.nix
  ];
}
