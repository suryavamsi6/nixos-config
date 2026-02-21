# Auto-imports all desktop modules
{ ... }:
{
  imports = [
    ./swaync.nix
    ./walker.nix
    ./ags.nix
    ./wallpapers.nix
    ./gtk-theme.nix
    ./greetd.nix
    ./gnome.nix
  ];
}
