{pkgs, ...}:
{
    imports = [
        ./cliModules/kitty.nix
        ./cliModules/sh.nix
        ./dotfiles/hyprland/hyprland.nix
    ];
}