{ pkgs, ... }:
{
  home.packages = with pkgs; [
    vscode
    superfile
    wget
    git
    kitty
    htop
    nixfmt-rfc-style
    vim
    jetbrains.webstorm
    code-cursor
    nix-init
    nixd
    yazi
  ];
}
