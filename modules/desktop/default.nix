# Auto-imports all desktop modules
{ ... }:
{
  imports = [
    ./swaync.nix
    ./hyprlauncher.nix
    ./ags.nix
    ./serpantinum.nix
    ./wallpapers.nix
    ./gtk-theme.nix
    ./greetd.nix
    ./gnome.nix
  ];
}
