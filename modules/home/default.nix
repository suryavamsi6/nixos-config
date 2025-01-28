{ ... }:
{
  imports = [
    ./cliModules/kitty.nix
    ./cliModules/sh.nix
    ./dotfiles/hyprland/hyprland.nix
    # ./dotfiles/hyprpanel/hyprpanel.nix
    ./systemModules/walker.nix
    ./dotfiles/ags/ags.nix
    ./dotfiles/hyprlock/hyprlock.nix
    ./wallpapers/wallpaper.nix
    ./dotfiles/hyprpaper/hyprpaper.nix
    #    ./systemModules/kanshi.nix
  ];
}
