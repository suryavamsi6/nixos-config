# MacBook M4 Air - home-manager configuration
{
  pkgs,
  lib,
  ...
}:
{
  home.username = "suryavamsi";
  home.homeDirectory = lib.mkForce "/Users/suryavamsi";

  home.stateVersion = "24.11";

  programs.home-manager.enable = true;

  # Fish shell with nix-darwin PATH integration
  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      # Disable default greeting
      set -g fish_greeting
    '';
    shellAbbrs = {
      rebuild = "sudo darwin-rebuild switch --flake ~/Dotfiles/nixos-config#macbook-air";
    };
    shellInit = ''
      # Add nix-darwin and nix profile paths
      fish_add_path --move --path /run/current-system/sw/bin
      fish_add_path --move --path /nix/var/nix/profiles/default/bin
    '';
  };

  # Starship prompt
  programs.starship = {
    enable = true;
    enableFishIntegration = true;
  };

  programs.nh = {
    enable = true;
    flake = "/Users/suryavamsi/Dotfiles/nixos-config";
  };

  # Git
  programs.git = {
    enable = true;
    userName = "Surya Vamsi";
    userEmail = "d.suryavamsi@gmail.com";
  };

  # Home packages
  home.packages = with pkgs; [
  ];
}
