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
        # Ori is intentionally rolling rather than pinned in the Nix store.
        # The launcher bootstraps the latest stable binary into user state;
        # Ori's own `ori update` command can then update that mutable copy.
        ori = pkgs.writeShellApplication {
          name = "ori";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.curl
            pkgs.gnugrep
            pkgs.patchelf
            pkgs.util-linux
          ];
          text = ''
            state_root="''${XDG_DATA_HOME:-$HOME/.local/share}/ori"
            bin_dir="$state_root/bin"
            binary="$bin_dir/ori"
            expected_interpreter="${pkgs.stdenv.cc.libc}/lib/ld-linux-x86-64.so.2"
            release_base="https://github.com/OpenRouterLabs/ori-releases/releases/latest/download"
            tmp_dir=""

            cleanup() {
              if [[ -n "$tmp_dir" ]]; then
                rm -rf "$tmp_dir"
              fi
            }
            trap cleanup EXIT

            mkdir -p "$bin_dir"
            exec 9>"$state_root/install.lock"
            flock 9

            if [[ ! -x "$binary" ]]; then
              tmp_dir="$(mktemp -d)"
              curl --fail --location --silent --show-error --proto '=https' \
                "$release_base/ori-linux-x64" -o "$tmp_dir/ori-linux-x64"
              curl --fail --location --silent --show-error --proto '=https' \
                "$release_base/SHA256SUMS" -o "$tmp_dir/SHA256SUMS"

              checksum_line="$(grep -E '^[[:xdigit:]]{64}[[:space:]]+\*?ori-linux-x64$' "$tmp_dir/SHA256SUMS" || true)"
              if [[ -z "$checksum_line" ]]; then
                echo "ori: latest release has no checksum for ori-linux-x64" >&2
                exit 1
              fi
              (
                cd "$tmp_dir"
                printf '%s\n' "$checksum_line" | sha256sum --check --status -
              )

              patchelf --set-interpreter "$expected_interpreter" "$tmp_dir/ori-linux-x64"
              install -m755 "$tmp_dir/ori-linux-x64" "$binary"
              rm -rf "$tmp_dir"
              tmp_dir=""
            fi

            current_interpreter="$(patchelf --print-interpreter "$binary" 2>/dev/null || true)"
            if [[ "$current_interpreter" != "$expected_interpreter" ]]; then
              patched_binary="$(mktemp "$bin_dir/.ori-patched.XXXXXX")"
              cp "$binary" "$patched_binary"
              chmod u+w "$patched_binary"
              patchelf --set-interpreter "$expected_interpreter" "$patched_binary"
              chmod 755 "$patched_binary"
              mv -f "$patched_binary" "$binary"
            fi

            flock -u 9
            exec env PATH="$bin_dir:''${PATH:-}" "$binary" "$@"
          '';
        };
        orcaProfileBin = "${config.home.profileDirectory}/bin/orca-ide";
        orcaDesktopItem = pkgs.makeDesktopItem {
          name = "orca-ide";
          desktopName = "Orca IDE";
          comment = "AI-native development environment";
          # Use the Nix FHS wrapper directly; Orca's CLI installer otherwise
          # creates a host-side symlink to the raw AppImage Electron binary.
          exec = "${orcaProfileBin} %U";
          categories = [ "Development" "IDE" ];
          startupNotify = true;
        };
        orca = pkgs.appimageTools.wrapType2 {
          pname = "orca-ide";
          version = "1.4.197";
          src = pkgs.fetchurl {
            url = "https://github.com/stablyai/orca/releases/download/v1.4.197/orca-linux.AppImage";
            hash = "sha256-S8hGLRUf8BD6pUxka7FtzFR0v2ZO7V7FAoGC15kmQWs=";
          };
          extraInstallCommands = ''
            install -Dm644 ${orcaDesktopItem}/share/applications/orca-ide.desktop $out/share/applications/orca-ide.desktop
          '';
        };
        emdashDesktopItem = pkgs.makeDesktopItem {
          name = "emdash";
          desktopName = "Emdash";
          comment = "Open-source agentic development environment";
          exec = "${config.home.profileDirectory}/bin/emdash %U";
          icon = "applications-development";
          categories = [ "Development" "IDE" ];
          startupNotify = true;
        };
        emdash = pkgs.appimageTools.wrapType2 {
          pname = "emdash";
          version = "1.2.4";
          src = pkgs.fetchurl {
            url = "https://github.com/generalaction/emdash/releases/download/v1.2.4/emdash-x86_64.AppImage";
            hash = "sha256-8+UhbYn6OE7R+6hyR0mx0h6n5H+3i+TWyIsEsbNa4Fs=";
          };
          extraInstallCommands = ''
            install -Dm644 ${emdashDesktopItem}/share/applications/emdash.desktop $out/share/applications/emdash.desktop
          '';
        };
        # because the package's plugin bundles use peer dependencies. Install
        # the OAuth provider into the persistent web profile on first launch.
        deepseekHarness = pkgs.writeShellScriptBin "deepseek-harness" ''
          export XDG_DATA_HOME="''${XDG_DATA_HOME:-$HOME/.local/share}/deepseek-harness"
          export NODE_PATH="${pkgs.pnpm}/lib/node_modules"
          exec ${pkgs.pnpm}/bin/pnpm dlx --package deepseek-harness@latest deepseek-harness "$@"
        '';
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
        # Code search & document retrieval. Resolve qmd lazily through npm so it
        # is available from the Nix profile without a global mutable install.
        qmd = pkgs.writeShellApplication {
          name = "qmd";
          runtimeInputs = [ pkgs.nodejs_22 ];
          text = ''
            exec npm exec --yes --package @tobilu/qmd@latest -- qmd "$@"
          '';
        };
        # Local browser automation harness. Distributed as an npm CLI and
        # resolved through pnpm to keep peer-dependency resolution consistent
        # with the other node CLIs in this module.
        agentBrowser = pkgs.writeShellScriptBin "agent-browser" ''
          exec ${pkgs.pnpm}/bin/pnpm dlx --package agent-browser@latest agent-browser "$@"
        '';
        # Hermes Desktop worker diagnostics. Run via pnpm so it shares the
        # same version resolver as the rest of the agent CLIs.
        piAgentBrowserDoctor = pkgs.writeShellScriptBin "pi-agent-browser-doctor" ''
          exec ${pkgs.pnpm}/bin/pnpm dlx --package @mariozechner/pi-agent-browser-doctor@latest pi-agent-browser-doctor "$@"
        '';
        # Feynman is an end-to-end coding agent CLI. It is published as an
        # npm bundle; we run it through pnpm so its optional peer
        # dependencies are installed on demand.
        feynman = pkgs.writeShellScriptBin "feynman" ''
          exec ${pkgs.pnpm}/bin/pnpm dlx --package feynman-coding-agent@latest feynman "$@"
        '';
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
        home.activation.orcaCliLink = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          # Orca's built-in CLI installer may recreate this link on launch. It
          # points at resources/bin/orca-ide, which bypasses appimageTools' FHS
          # wrapper and triggers NixOS' dynamic-linker stub. Remove only that
          # known stale store link; do not disturb an unrelated user command.
          if [ -L "$HOME/.local/bin/orca-ide" ]; then
            target="$(readlink "$HOME/.local/bin/orca-ide")"
            case "$target" in
              /nix/store/*-orca-ide-*/resources/bin/orca-ide)
                rm "$HOME/.local/bin/orca-ide"
                ;;
            esac
          fi
        '';
        home.activation.piConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          install -Dm644 ${./pi-settings.json} "$HOME/.pi/agent/settings.json"
          install -Dm644 ${./pi-models.json} "$HOME/.pi/agent/models.json"
          install -Dm644 ${./pi-mcp.json} "$HOME/.pi/agent/mcp.json"
        '';
        # Code launcher for the Codex CLI. Super+Space ignores Terminal=true,
        # so the desktop entry launches it explicitly through Ghostty.
        xdg.desktopEntries.codex-cli = {
          name = "Codex CLI";
          comment = "OpenAI Codex in the terminal";
          exec = "${lib.getExe pkgs.ghostty} --title Codex -e ${lib.getExe pkgs.codex}";
          icon = "utilities-terminal";
          categories = [ "Development" ];
        };

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
          ori
          bun
          codex
          herdr
          piBootstrap
          deepseekHarness
          piAgent
          qmd
          agentBrowser
          piAgentBrowserDoctor
          feynman
          emdash
          t3code
          orca
          inputs.hunk.packages.${pkgs.stdenv.hostPlatform.system}.hunk
          opencode
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
