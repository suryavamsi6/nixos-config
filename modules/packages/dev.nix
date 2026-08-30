# Dev tools (home-manager)
{ lib, ... }:
{
  options.flake.modules.homeManager.dev = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { pkgs, inputs, config, lib, ... }:
      let
        # pkgs.codex is CLI-only. Super+Space ignores Terminal=true.
        codexCliDesktop = pkgs.makeDesktopItem {
          name = "codex-cli";
          desktopName = "Codex CLI";
          comment = "OpenAI Codex in the terminal";
          exec = "${lib.getExe pkgs.ghostty} --title Codex -e ${lib.getExe pkgs.codex}";
          icon = "utilities-terminal";
          categories = [ "Development" ];
        };
        ohMyPi = pkgs.stdenvNoCC.mkDerivation {
          pname = "oh-my-pi";
          version = "18.0.6";
          src = pkgs.fetchurl {
            url = "https://github.com/can1357/oh-my-pi/releases/download/v18.0.6/omp-linux-x64";
            hash = "sha256-nLx4vpumNXtTpqBVyYrXr+5MANIKMg1Ru3apSbilpEQ=";
          };
          nativeBuildInputs = [ pkgs.patchelf ];
          dontUnpack = true;
          installPhase = ''
            install -Dm755 "$src" "$out/bin/omp"
            patchelf --set-interpreter ${pkgs.stdenv.cc.libc}/lib/ld-linux-x86-64.so.2 "$out/bin/omp"
          '';
        };
        # DeepSeek Harness is published as an npm CLI. pnpm is required here
        # because the package's plugin bundles use peer dependencies. Install
        # the OAuth provider into the persistent web profile on first launch.
        deepseekHarness = pkgs.writeShellApplication {
          name = "dsh";
          runtimeInputs = [ pkgs.nodejs_22 pkgs.pnpm pkgs.gnused ];
          text = ''
            # shellcheck disable=SC2016
            exec pnpm dlx --package @deepseek-ai/dsh@0.1.1-rc.2 sh -c '
              shim=$(command -v dsh)
              script=$(sed -n "s/^# cmd-shim-target=//p" "$shim")
              profile="$HOME/.dsh/profiles/web"
              if [ ! -e "$profile/node_modules/dsh-openai-oauth" ]; then
                node --expose-internals "$script" plugin --profile web add dsh-openai-oauth
              fi
              exec node --expose-internals "$script" "$@"
            ' dsh "$@"
          '';
        };
        piAgent = pkgs.writeShellApplication {
          name = "pi";
          runtimeInputs = [
            pkgs.nodejs_22
            pkgs.pnpm
            pkgs.gnumake
            pkgs.gcc
            pkgs.python3
          ];
          text = ''
            exec npm exec --yes --package @earendil-works/pi-coding-agent@latest -- pi "$@"
          '';
        };
        # Install these manually with: pi install <extension>
        piExtensions = [
          "npm:@ff-labs/pi-fff"
          "npm:@narumitw/pi-lsp"
          "npm:pi-subagents"
          "npm:@narumitw/pi-plan-mode"
          "npm:pi-mcp-adapter"
          "npm:pi-linehash-edit"
          "npm:@gotgenes/pi-permission-system"
          "npm:pi-web-access"
          "npm:@juicesharp/rpiv-ask-user-question"
          "npm:pi-background-tasks"
          "npm:context-mode"
          "npm:pi-hermes-memory"
          "npm:@zosmaai/pi-llm-wiki"
          "npm:pi-cc-header"
          "npm:better-claude-code-ui"
        ];
      in
      {
        imports = [ inputs.codex-desktop-linux.homeManagerModules.default ];

        # ChatGPT desktop app (Chat + Work + Codex UI). cliPackage so the
        # Electron wrapper finds pkgs.codex from Super+Space.
        programs.codexDesktopLinux = {
          enable = true;
          cliPackage = pkgs.codex;
        };

        xdg.desktopEntries.codex = {
          name = "Codex";
          comment = "OpenAI Codex desktop";
          exec = "${config.home.profileDirectory}/bin/codex-desktop";
          icon = "codex-desktop";
          categories = [ "Development" ];
          startupNotify = true;
        };

        home.packages = with pkgs; [
          superfile
          wget
          git
          ghostty
          htop
          nixfmt
          vim
          antigravity-ide
          nix-init
          nixd
          yazi
          treefmt
          tmux
          dig
          code-cursor
          codex
          ohMyPi
          deepseekHarness
          piAgent
          codexCliDesktop
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
                    "expr" :"(builtins.getFlake \"/home/surya/Dotfiles/nixos-config\").inputs.nixpkgs {}",
                  },
                  "formatting" :{
                    "command" :[ "nixfmt" ],
                  },
                  "options" :{
                    "nixos" :{
                      "expr" :"(builtins.getFlake \"/home/surya/Dotfiles/nixos-config\").nixosConfigurations.nixos.options",
                    },
                  },
                },
                "workbench.colorTheme": "Catppuccin Mocha",
                "workbench.iconTheme": "catppuccin-mocha",

            }
          '';
        };
        home.file.".agents/git-ops.md" = {
          source = ../../.agents/git-ops.md;
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
