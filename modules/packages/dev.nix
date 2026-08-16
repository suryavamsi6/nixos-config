# Dev tools (home-manager)
{ lib, ... }:
{
  options.flake.modules.homeManager.dev = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { pkgs, ... }:
      {
        home.packages = with pkgs; [
          superfile
          wget
          git
          kitty
          htop
          nixfmt
          vim
          antigravity-ide
          nix-init
          nixd
          yazi
          treefmt
          kitty-themes
          tmux
          dig
          code-cursor
          chntpw
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
              {
                name = "geminicodeassist";
                publisher = "Google";
                version = "2.27.4";
                sha256 = "sha256-RHePV7ziovUSyxIIjVSKCXxVBRfJ6vvbO6t7S2B/P7U=";
              }
              {
                name = "remote-ssh";
                publisher = "ms-vscode-remote";
                version = "0.121.2025050915";
                sha256 = "sha256-lDt3ADiiIc7pHhytbxIBXkEoBmCOf36z2TPMhYOzyA0=";
              }
            ];
          })
        ];

        programs.git = {
          enable = true;
          settings = {
            user.name = "Surya Vamsi";
            user.email = "d.suryavamsi@gmail.com";
            # Public key, safe to commit. 1Password holds the private half.
            user.signingkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDGneR+cI5ZQWog3zHRj1MvP3ek+1MikaD6uPY9hrmW+";
            commit.gpgsign = true;
            gpg.format = "ssh";
            # 1Password's own setup writes /opt/1Password/op-ssh-sign into
            # ~/.gitconfig, which does not exist on NixOS and fails every
            # commit. Remove that file so this config is the only global one:
            # git reads ~/.gitconfig after ~/.config/git/config, so it wins.
            gpg.ssh.program = lib.getExe' pkgs._1password-gui "op-ssh-sign";
          };
        };

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
      };
  };

  # Darwin-specific dev tools (home-manager)
  options.flake.modules.homeManager.devDarwin = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { pkgs, ... }:
      {
        programs.nh = {
          enable = true;
          flake = "/Users/suryavamsi/Dotfiles/nixos-config";
        };

        programs.git = {
          enable = true;
          settings.user.name = "Surya Vamsi";
          settings.user.email = "d.suryavamsi@gmail.com";
        };
      };
  };
}
