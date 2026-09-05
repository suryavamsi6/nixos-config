# Dev tools (home-manager)
{ lib, ... }:
{
  options.flake.modules.homeManager.dev = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      {
        pkgs,
        inputs,
        config,
        lib,
        ...
      }:
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
          runtimeInputs = [
            pkgs.nodejs_22
            pkgs.pnpm
            pkgs.gnused
          ];
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
        piBootstrap = pkgs.writeShellApplication {
          name = "pi-bootstrap";
          runtimeInputs = [ pkgs.coreutils ];
          text = ''
            set -eu
            for package in ${lib.escapeShellArgs piPackages}; do
              echo "Installing or reconciling $package"
              ${piAgent}/bin/pi install "$package"
            done
          '';
        };
        agentBrowser = pkgs.stdenvNoCC.mkDerivation {
          pname = "agent-browser";
          version = "0.34.0";
          src = pkgs.fetchurl {
            url = "https://registry.npmjs.org/agent-browser/-/agent-browser-0.34.0.tgz";
            hash = "sha256-pHRPsYnlmEZ6vPs6zd4HEY2eXLQ9w7MXJ/hpr0651Zg=";
          };
          nativeBuildInputs = [
            pkgs.makeWrapper
            pkgs.patchelf
          ];
          dontUnpack = true;
          installPhase = ''
            mkdir -p "$out/libexec/agent-browser" "$out/bin";
            tar -xzf "$src" -C "$out/libexec/agent-browser" --strip-components=1;
            chmod +x "$out/libexec/agent-browser/bin/agent-browser-linux-x64";
            patchelf --set-interpreter "${pkgs.stdenv.cc.libc}/lib/ld-linux-x86-64.so.2" \
              "$out/libexec/agent-browser/bin/agent-browser-linux-x64";
            makeWrapper "$out/libexec/agent-browser/bin/agent-browser.js" "$out/bin/agent-browser" \
              --prefix PATH : "${pkgs.nodejs_24}/bin";
          '';
        };
        piAgentBrowserDoctor = pkgs.writeShellApplication {
          name = "pi-agent-browser-doctor";
          runtimeInputs = [ pkgs.nodejs_22 ];
          text = ''
            exec npm exec --yes --package pi-agent-browser-native@latest -- pi-agent-browser-doctor "$@"
          '';
        };
        qmd = pkgs.writeShellApplication {
          name = "qmd";
          runtimeInputs = [ pkgs.nodejs_22 ];
          text = ''
            exec npm exec --yes --package @tobilu/qmd@latest -- qmd "$@"
          '';
        };
        # Always use the latest Feynman research CLI; npm refreshes it when invoked.
        feynman = pkgs.writeShellApplication {
          name = "feynman";
          runtimeInputs = [ pkgs.nodejs_22 ];
          text = ''
            exec npm exec --yes --package @companion-ai/feynman@latest -- feynman "$@"
          '';
        };
        # Pi package sources are declared in pi-settings.json and installed by
        # the `pi-bootstrap` command after the Home Manager generation applies.
        piPackages = [
          "npm:@ff-labs/pi-fff"
          "npm:@narumitw/pi-lsp"
          "npm:pi-subagents"
          "npm:pi-mcp-adapter"
          "npm:pi-linehash-edit"
          "npm:@gotgenes/pi-permission-system"
          "npm:pi-zentui"
          "npm:pi-memory"
          "npm:@juicesharp/rpiv-ask-user-question"
          "npm:pi-background-tasks"
          "npm:context-mode"
          "npm:pi-web-access"
          "npm:@plannotator/pi-extension"
          "npm:@narumitw/pi-usage"
          "npm:pi-opencode-free"
          "npm:@agent-sh/computer-use-linux"
          "npm:@juicesharp/rpiv-todo"
          "npm:pi-agent-browser-native"
          "npm:@henryqw/pi-task-models"
          "npm:@henryqw/pi-herdr"
          "npm:@henryqw/pi-herdr-rename"
          "npm:pi-cache-optimizer"
          "npm:pi-stats-dashboard"
          "git:github.com/nagisanzenin/engram"
        ];
      in
      {
        imports = [ inputs.codex-desktop-linux.homeManagerModules.default ];
        # Copy instead of symlinking: Pi updates settings.json during `pi install`.
        home.activation.piConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          install -Dm644 ${./pi-settings.json} "$HOME/.pi/agent/settings.json"
          install -Dm644 ${./pi-models.json} "$HOME/.pi/agent/models.json"
          install -Dm644 ${./pi-mcp.json} "$HOME/.pi/agent/mcp.json"
        '';

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
          gh
          rtk
          ghostty
          htop
          nixfmt
          vim
          nix-init
          nixd
          yazi
          treefmt
          tmux
          dig
          procps
          code-cursor
          codex
          herdr
          piBootstrap
          deepseekHarness
          piAgent
          qmd
          agentBrowser
          piAgentBrowserDoctor
          feynman
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
        home.packages = [ pkgs.gh ];

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
