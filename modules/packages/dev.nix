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
        opencodeUpstream = inputs.opencode.packages.${pkgs.stdenv.hostPlatform.system}.opencode;
        opencodeV2 = (opencodeUpstream.override {
          # v2.0.15's upstream node_modules hash is stale; use the hash
          # produced by the pinned source and Bun toolchain.
          node_modules = opencodeUpstream.node_modules.overrideAttrs (_: {
            outputHash = "sha256-H9G54uuDIuPaQ3d9db/LmdtJ/OUDQodIkqdy6AHtPWo=";
          });
        }).overrideAttrs (_: {
          # v2.0.15's completion subcommand is broken in the Nix build sandbox.
          postInstall = "";
        });
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
        # ZCode is Z.ai's agentic development environment and ships Linux
        # builds only. appimageTools extracts the AppImage at build time, which
        # keeps it off FUSE at runtime; the app itself then runs inside the FHS
        # env below, because its Electron binary wants
        # /lib64/ld-linux-x86-64.so.2 — on the desktop hosts that is NixOS'
        # stub-ld, not a real loader.
        zcodeVersion = "3.14.4";
        zcodeSrc = pkgs.fetchurl {
          url = "https://cdn-zcode.z.ai/zcode/electron/releases/${zcodeVersion}/linux-x64/ZCode-${zcodeVersion}-linux-x64.AppImage";
          hash = "sha256-S0YxmHFy/ZdaofhfoNwfVawcdWsmvYqxjWhZLtk5EYI=";
        };
        # Exactly the arguments wrapType2 extracts internally, so this is that
        # same derivation: the icons installed below come for free instead of
        # paying for a second unpacked copy in the store.
        zcodeContents = pkgs.appimageTools.extract {
          pname = "zcode";
          version = zcodeVersion;
          src = zcodeSrc;
        };
        # A hand-rolled wrapType2 with two deliberate differences: the chroot is
        # named zcode-fhsenv so the `zcode` command below can be the redirecting
        # wrapper, and nodejs_22 is added for the agent's `npx` MCP servers (the
        # AppImage bundles its own ripgrep, bfs and ugrep, and the chroot
        # already provides xdg-utils).
        zcodeFhsenv = pkgs.buildFHSEnv (
          pkgs.appimageTools.defaultFhsEnvArgs
          // {
            name = "zcode-fhsenv";
            runScript = "appimage-exec.sh -w ${zcodeContents} --";
            targetPkgs =
              p:
              [ pkgs.appimageTools.appimage-exec ]
              ++ pkgs.appimageTools.defaultFhsEnvArgs.targetPkgs p
              ++ [ p.nodejs_22 ];
          }
        );
        zcodeLauncher = pkgs.writeShellApplication {
          name = "zcode";
          text = ''
            export XDG_DATA_HOME="''${XDG_DATA_HOME:-$HOME/.local/share}/zcode-app"
            exec ${zcodeFhsenv}/bin/zcode-fhsenv "$@"
          '';
        };
        # The icons have to ride in the package that home.packages installs —
        # the entry's Icon=zcode resolves through the profile's icon theme —
        # while the chroot itself stays out of the profile, so nothing but this
        # wrapper ends up on PATH.
        zcode = pkgs.runCommandLocal "zcode" { } ''
          install -Dm755 ${zcodeLauncher}/bin/zcode $out/bin/zcode
          for size in 48x48 128x128 256x256; do
            install -Dm644 ${zcodeContents}/usr/share/icons/hicolor/$size/apps/zcode.png \
              $out/share/icons/hicolor/$size/apps/zcode.png
          done
        '';
        # Super+Space entry for ZCode: it has to be the zcode.desktop that
        # mimeapps.list points at for zcode://, and it is installed through the
        # xdg.dataFile entry below so its Exec stays this wrapper.
        zcodeDesktopItem = pkgs.makeDesktopItem {
          name = "zcode";
          desktopName = "ZCode";
          comment = "Z.ai agentic development environment";
          exec = "${config.home.profileDirectory}/bin/zcode %U";
          icon = "zcode";
          mimeTypes = [ "x-scheme-handler/zcode" ];
          categories = [ "Development" "IDE" ];
          startupNotify = true;
        };
        # AutoClaw is Z.ai's other desktop agent: an Electron shell around a
        # bundled OpenClaw gateway. Linux is published as a .deb only, so
        # unpack it the way its own postinst does and run the tree inside the
        # same FHS environment the AppImage apps above get from appimageTools'
        # defaults — Electron's interpreter/loader expectations are the same
        # problem wrapType2 solves for them. Linux builds are x86_64-only.
        autoclawVersion = "1.18.5";
        autoclawDeb = pkgs.fetchurl {
          url = "https://autoglm.oss-cn-beijing.aliyuncs.com/autoclaw/updates/autoclaw_${autoclawVersion}_amd64.deb";
          hash = "sha256-fCu3V9Qs3ifYhzyQrzItb5Q6nx5ylzzC76NPjMKwR78=";
        };
        autoclawUnpacked = pkgs.runCommand "autoclaw-${autoclawVersion}-unpacked" {
          nativeBuildInputs = [ pkgs.dpkg ];
        } ''
          dpkg-deb -x ${autoclawDeb} $out
          # The deb carries the 500M gateway runtime as a single tar and its
          # postinst unpacks it here (60k files would otherwise make dpkg
          # fsync forever). The app starts with a broken gateway without this.
          tar -xf $out/opt/AutoClaw/resources/gateway.tar \
            -C $out/opt/AutoClaw/resources --no-same-owner
          rm -f $out/opt/AutoClaw/resources/gateway.tar
        '';
        autoclawDesktopItem = pkgs.makeDesktopItem {
          name = "autoclaw";
          desktopName = "AutoClaw";
          comment = "Desktop AI Cowork Platform powered by OpenClaw Gateway";
          exec = "${config.home.profileDirectory}/bin/autoclaw %U";
          icon = "autoclaw";
          categories = [ "Utility" ];
          startupNotify = true;
        };
        autoclaw = pkgs.buildFHSEnv (
          pkgs.appimageTools.defaultFhsEnvArgs
          // {
            name = "autoclaw";
            runScript = "${autoclawUnpacked}/opt/AutoClaw/autoclaw";
            # The deb's Depends beyond that chroot list: libsecret for the
            # keyring (nss, libxtst, xdg-utils, at-spi and libnotify are
            # already provided there).
            targetPkgs =
              p: pkgs.appimageTools.defaultFhsEnvArgs.targetPkgs p ++ (with p; [ libsecret ]);
            extraInstallCommands = ''
              install -Dm644 ${autoclawDesktopItem}/share/applications/autoclaw.desktop $out/share/applications/autoclaw.desktop
              # Upstream ships 16/32/128 only.
              for size in 16x16 32x32 128x128; do
                install -Dm644 ${autoclawUnpacked}/usr/share/icons/hicolor/$size/apps/autoclaw.png \
                  $out/share/icons/hicolor/$size/apps/autoclaw.png
              done
            '';
            meta = {
              description = "AI cowork desktop app powered by the OpenClaw gateway";
              homepage = "https://autoclaw.z.ai/";
              platforms = [ "x86_64-linux" ];
            };
          }
        );
        # because the package's plugin bundles use peer dependencies. Install
        # the OAuth provider into the persistent web profile on first launch.
        deepseekHarness = pkgs.writeShellScriptBin "deepseek-harness" ''
          export XDG_DATA_HOME="''${XDG_DATA_HOME:-$HOME/.local/share}/deepseek-harness"
          export NODE_PATH="${pkgs.pnpm}/lib/node_modules"
          exec ${pkgs.pnpm}/bin/pnpm dlx --package deepseek-harness@latest deepseek-harness "$@"
        '';
        # pi's extension packages must resolve the host-provided packages
        # (pi-ai, pi-agent-core, pi-coding-agent, pi-tui) from the pi
        # installation that is actually running. npm reifies
        # ~/.pi/agent/npm from the registry and prunes those links as
        # extraneous, so both the `pi` wrapper and the npmCommand shim
        # re-create them. See modules/packages/pi-host-links.mjs.
        piHostLinks = pkgs.writeShellApplication {
          name = "pi-host-links";
          runtimeInputs = [ pkgs.nodejs_22 ];
          text = ''
            exec node ${./pi-host-links.mjs} "$@"
          '';
        };
        # `npm exec` exports every resolved npm configuration value as
        # npm_config_* into the child environment. Left in place, pi and every
        # process it spawns inherit them. npm_config_package is the damaging
        # one: a nested `npx <pkg>` then reads the package spec as the command
        # to run and dies with "command not found", which is what broke the
        # canva stdio MCP server (`npx -y mcp-remote@latest <url>`). Strip the
        # variables so pi runs with the environment a plain terminal gives it.
        piCleanEnv = pkgs.writeShellApplication {
          name = "pi-clean-env";
          runtimeInputs = [ pkgs.coreutils ];
          text = ''
            names=()
            while IFS='=' read -r name _; do
              if [[ "$name" == npm_config_* ]]; then
                names+=("$name")
              fi
            done < <(env)
            if (( "''${#names[@]}" > 0 )); then
              unset "''${names[@]}"
            fi
            exec pi "$@"
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
            piHostLinks
            piCleanEnv
          ];
          text = ''
            # Repair host-provided dependency links before pi loads extensions,
            # so a pruned ~/.pi/agent/npm never surfaces as a load error.
            pi-host-links >/dev/null || true

            # Do not exec: the wrapper re-runs the repair after pi exits, which
            # is what creates the links the first time after a fresh npx
            # install of pi-coding-agent.
            #
            # pi-clean-env strips the npm_config_* variables `npm exec` exports
            # into the child environment before starting pi (see its definition).
            pi_status=0
            npm exec --yes --package @earendil-works/pi-coding-agent@latest -- pi-clean-env "$@" || pi_status=$?
            pi-host-links >/dev/null || true
            exit "$pi_status"
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
          "npm:pi-linehash-edit"
          "npm:@gotgenes/pi-permission-system"
          "npm:pi-zentui"
          "npm:pi-memory"
          "npm:@sherif-fanous/pi-rtk"
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
          "npm:billion-context"
          "npm:pi-goal-x"
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
          piSettings="$HOME/.pi/agent/settings.json"
          # /model and /thinking persist the defaults saved with Ctrl+S into
          # this same file, so copying the template over it wholesale resets the
          # default model on every switch. The template stays authoritative for
          # flake-managed keys (packages, subagents, UI prefs); only the
          # pi-owned keys below carry over from the live file. Deliberately not
          # listed here: anything the flake declares, e.g. defaultModel lives
          # only in the live file now — see modules/packages/pi-settings.json.
          piOwnedKeys='["defaultProvider","defaultModel","defaultThinkingLevel","modelThinkingLevels","enabledModels","lastChangelogVersion"]'
          if [ -f "$piSettings" ]; then
            piMerged="$(${pkgs.jq}/bin/jq -s --argjson keys "$piOwnedKeys" \
              '.[0] + (.[1] | with_entries(select(.key as $k | $keys | index($k))))' \
              ${./pi-settings.json} "$piSettings" 2>/dev/null || true)"
            if [ -n "$piMerged" ]; then
              printf '%s\n' "$piMerged" > "$piSettings.new"
              mv "$piSettings.new" "$piSettings"
            else
              install -Dm644 ${./pi-settings.json} "$piSettings"
            fi
          else
            install -Dm644 ${./pi-settings.json} "$piSettings"
          fi
          rm -f "$piSettings.new"
          install -Dm644 ${./pi-models.json} "$HOME/.pi/agent/models.json"
          # MCP servers are pi's own now (`~/.pi/agent/mcp.json`, see
          # docs/mcp.md). The `pi-mcp-adapter` extension that used to own this
          # file is gone, so write the server list where pi core reads it and
          # drop the adapter's copy.
          install -Dm644 ${./pi-mcp.json} "$HOME/.pi/agent/mcp.json"
          rm -f "$HOME/.pi/agent/mcp-adapter.json"
          # The npmCommand shim and the host-dependency repairs it drives are
          # referenced by ~/.pi/agent/settings.json, so keep them in sync with
          # the flake rather than as hand-edited files.
          install -Dm755 ${./pi-npm} "$HOME/.pi/agent/bin/pi-npm"
          install -Dm755 ${./host-deps-patch.mjs} "$HOME/.pi/agent/bin/host-deps-patch.mjs"
          install -Dm755 ${./pi-host-links.mjs} "$HOME/.pi/agent/bin/pi-host-links.mjs"
        '';

        # AutoClaw's only Linux build is the mainland (zhipuai.cn) one and it
        # seeds a Simplified-Chinese UI; the language lives in the app's own
        # settings file. The same build ships en-US, so pin it here — with the
        # app running the file can be rewritten from memory, hence an
        # activation rather than a one-off edit. Drop this block to let the
        # in-app Settings → Appearance choice win instead.
        home.activation.autoclawLanguage = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          autoclawSettings="$HOME/.config/autoclaw/settings.json"
          if [ -f "$autoclawSettings" ]; then
            if ${pkgs.jq}/bin/jq '.appearance.language = "en-US"' "$autoclawSettings" > "$autoclawSettings.new"; then
              mv "$autoclawSettings.new" "$autoclawSettings"
            fi
            rm -f "$autoclawSettings.new"
          else
            # Seed a fresh install so the first launch is English too; the app
            # fills in its remaining defaults on start.
            mkdir -p "$HOME/.config/autoclaw"
            printf '%s\n' '{"appearance":{"language":"en-US"}}' > "$autoclawSettings"
          fi
        '';

        # ZCode's zcode:// deep-link registration lives in the app's private
        # XDG data dir (see the `zcode` wrapper above), which is what lets this
        # entry stay in the launcher. That directory is searched before
        # XDG_DATA_DIRS, so an entry shipped from the package itself
        # (xdg.desktopEntries) would still be shadowed and could not be trusted
        # to keep an Exec that works. force = true because an app-written
        # regular file from before this existed would otherwise make Home
        # Manager's link check abort the activation.
        xdg.dataFile."applications/zcode.desktop" = {
          source = "${zcodeDesktopItem}/share/applications/zcode.desktop";
          force = true;
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
          herdr
          piBootstrap
          deepseekHarness
          piAgent
          piHostLinks
          qmd
          agentBrowser
          piAgentBrowserDoctor
          feynman
          emdash
          zcode
          autoclaw
          t3code
          orca
          inputs.hunk.packages.${pkgs.stdenv.hostPlatform.system}.hunk
          opencodeV2
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
