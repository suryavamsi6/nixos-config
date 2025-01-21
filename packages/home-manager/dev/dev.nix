{ pkgs, ... }:
{
  home.packages = with pkgs; [
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

  programs.git.userName = "suryavamsi6";
  programs.git.userEmail = "d.suryavamsi@gmail.com";

  programs.vscode = {
    enable = true;
    userSettings = {
      "window.commandCenter" = true;
      "editor.defaultFormatter" = "jnoortheen.nix-ide";
      "editor.formatOnSave" = true;
      "nix.enableLanguageServer" = true;
      "files.autoSave" = "afterDelay";
      "nix.serverPath" = "nixd";
      "nix.serverSettings" = {
        "nixpkgs" = {
          "expr" = "(builtins.getFlake \"home/surya/Dotfiles/nixos/\").inputs.nixpkgs {}";
        };
        "formatting" = {
          "command" = [ "nixfmt" ];
        };
        "options" = {
          "nixos" = {
            "expr" = "(builtins.getFlake \"home/surya/Dotfiles/nixos/\").nixosConfigurations.nixos.options";
          };
          "home_manager" = {
            "expr" = "(builtins.getFlake \"home/surya/Dotfiles/nixos/\").homeConfigurations.nixos.options";
          };
        };
      };
    };
  };
}
