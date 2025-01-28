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
    treefmt
    kitty-themes
    (vscode-with-extensions.override {
      vscodeExtensions = pkgs.vscode-utils.extensionsFromVscodeMarketplace [
        {
          name = "nix-ide";
          publisher = "jnoortheen";
          version = "0.4.2";
          sha256 = "sha256-WOzHHQZlTdDoVB90GYhuEORNPLyv/lWZBNMrIzBTWW8=";
        }
        {
          name = "catppuccin-vsc";
          publisher = "Catppuccin";
          version = "3.16.0";
          sha256 = "sha256-eZwi5qONiH+XVZj7u2cjJm+Liv1q07AEd8d4nXEQgLw=";
        }
        {
          name = "catppuccin-vsc-icons";
          publisher = "Catppuccin";
          version = "1.17.0";
          sha256 = "sha256-CSAIDlZNrelBf891ztK4n9IaRdtXqpeXnI00hG0/nfA=";
        }
      ];
    })
  ];

  programs.git.userName = "suryavamsi6";
  programs.git.userEmail = "d.suryavamsi@gmail.com";

  home.file.".config/Code/User/settings.json" = {
    text = ''
      {
          "window.commandCenter" : true,
          "editor.defaultFormatter" :"jnoortheen.nix-ide",
          "editor.formatOnSave" :true,
          "nix.enableLanguageServer" :true,
          "files.autoSave" :"afterDelay",
          "nix.serverPath" :"nixd",
          "nix.serverSettings" : {
            "nixpkgs" :{
              "expr" :"(builtins.getFlake \"home/surya/Dotfiles/nixos/\").inputs.nixpkgs {}",
            },
            "formatting" :{
              "command" :[ "nixfmt" ],
            },
            "options" :{
              "nixos" :{
                "expr" :"(builtins.getFlake \"home/surya/Dotfiles/nixos/\").nixosConfigurations.nixos.options",
              },
              "home_manager" :{
                "expr" :"(builtins.getFlake \"home/surya/Dotfiles/nixos/\").homeConfigurations.nixos.options",
              },
            },
          },
          "workbench.colorTheme": "Catppuccin Mocha",
          "workbench.iconTheme": "catppuccin-mocha",

      }
    '';
  };

}
