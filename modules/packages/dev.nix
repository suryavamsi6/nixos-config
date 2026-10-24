# Dev tools (home-manager)
{ lib, ... }:
let
  # Shared with the NixOS dev module below. The Mac imports this on its own.
  piModule =
    { pkgs, lib, ... }:
    let
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

      # Hermes Desktop worker diagnostics. Run via pnpm so it shares the
      # same version resolver as the rest of the agent CLIs.
      piAgentBrowserDoctor = pkgs.writeShellScriptBin "pi-agent-browser-doctor" ''
        exec ${pkgs.pnpm}/bin/pnpm dlx --package @mariozechner/pi-agent-browser-doctor@latest pi-agent-browser-doctor "$@"
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
        "npm:@dietrichgebert/ponytail"
        "git:github.com/nagisanzenin/engram"
      ];
    in
    {
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

      home.packages = [
        piBootstrap
        piAgent
        piHostLinks
        piAgentBrowserDoctor
      ];
    };
in
{
  options.flake.modules.homeManager.pi = lib.mkOption {
    type = lib.types.deferredModule;
    default = piModule;
  };

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
        # The nix packaging takes src from a fileset filter that omits the
        # repo-root script/ dir, but packages/cli/script/build.ts imports
        # ../../../script/native-arch. Build from the unfiltered flake source
        # instead. (The v2.0.15-era node_modules hash and completion-subcommand
        # overrides are obsolete and were removed.)
        opencodeV2 = opencodeUpstream.overrideAttrs (_: {
          src = inputs.opencode.outPath;
        });
        ohMyPi = pkgs.stdenvNoCC.mkDerivation {
          pname = "oh-my-pi";
          version = "18.12.6";
          src = pkgs.fetchurl {
            url = "https://github.com/can1357/oh-my-pi/releases/download/v18.12.6/omp-linux-x64";
            hash = "sha256-hdna86Bfx26M1CWuGQTrV2r40hzIX89GkHQmJuB8z6Q=";
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
          categories = [
            "Development"
            "IDE"
          ];
          startupNotify = true;
        };
        orca = pkgs.appimageTools.wrapType2 {
          pname = "orca-ide";
          version = "1.4.237";
          src = pkgs.fetchurl {
            url = "https://github.com/stablyai/orca/releases/download/v1.4.237/orca-linux.AppImage";
            hash = "sha256-waZj6I2nCh/prgIawagq2tK92ugl+dcWU57ufmnH7yk=";
          };
          extraInstallCommands = ''
            install -Dm644 ${orcaDesktopItem}/share/applications/orca-ide.desktop $out/share/applications/orca-ide.desktop
          '';
        };
        # ZCode is Z.ai's agentic development environment and ships Linux
        # builds only. appimageTools extracts the AppImage at build time, which
        # keeps it off FUSE at runtime; the app itself then runs inside the FHS
        # env below, because its Electron binary wants
        # /lib64/ld-linux-x86-64.so.2 — on the desktop hosts that is NixOS'
        # stub-ld, not a real loader.
        zcodeVersion = "3.16.3";
        zcodeSrc = pkgs.fetchurl {
          url = "https://cdn-zcode.z.ai/zcode/electron/releases/${zcodeVersion}/linux-x64/ZCode-${zcodeVersion}-linux-x64.AppImage";
          hash = "sha256-SdAHZHuDHuUiDuNNCX4Dj7iaLfLGhrl6o7awLn0KC6I=";
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
          categories = [
            "Development"
            "IDE"
          ];
          startupNotify = true;
        };
        # OpenResearch (openresearch.sh, alphaXiv) is an agentic ML research
        # desktop whose Linux build is an AppImage wrapping an `orx` GUI
        # (AppRun ignores argv and always launches `orx app`). The bundled
        # binary wants /lib64/ld-linux-x86-64.so.2 — NixOS' stub-ld here — so
        # the extracted tree runs in a buildFHSEnv, like zcode. The
        # runScript must unset APPIMAGE: orx classifies its install from that
        # variable, and with it set the app treats itself as a self-updating
        # AppImage — it rewrites the desktop entry to the store AppImage path
        # (which cannot start on NixOS) and downloads itself a new AppImage.
        # Unset, the /nix/store path lands in InstallChannel::Nix and updates
        # stay with this flake. Agents drive the separate static-musl `orx`
        # CLI from the same release (below); GUI and CLI share
        # ~/.config/openresearch. Bump: version + both fetchurl hashes.
        openresearchVersion = "0.2.19";
        openresearchSrc = pkgs.fetchurl {
          url = "https://github.com/alphaXiv/OpenResearch/releases/download/v${openresearchVersion}/OpenResearch-x86_64.AppImage";
          hash = "sha256-+mWINFT8JrLMTid8aaICEdks6VZnHdXBa+s+rXDQxDw=";
        };
        openresearchContents = pkgs.appimageTools.extract {
          pname = "openresearch";
          version = openresearchVersion;
          src = openresearchSrc;
        };
        openresearchRun = pkgs.writeShellScript "openresearch-run" ''
          # See above: APPIMAGE would flip orx into AppImage self-update mode.
          unset APPIMAGE
          exec appimage-exec.sh -w ${openresearchContents} -- "$@"
        '';
        openresearchDesktopItem = pkgs.makeDesktopItem {
          name = "openresearch";
          desktopName = "OpenResearch";
          comment = "Automated ML research with your coding agents";
          exec = "${config.home.profileDirectory}/bin/openresearch %U";
          icon = "OpenResearch";
          categories = [ "Development" ];
          startupWMClass = "OpenResearch";
        };
        openresearch = pkgs.buildFHSEnv (
          pkgs.appimageTools.defaultFhsEnvArgs
          // {
            name = "openresearch";
            runScript = "${openresearchRun}";
            targetPkgs =
              p: [ pkgs.appimageTools.appimage-exec ] ++ pkgs.appimageTools.defaultFhsEnvArgs.targetPkgs p;
            extraInstallCommands = ''
              install -Dm644 ${openresearchDesktopItem}/share/applications/openresearch.desktop $out/share/applications/openresearch.desktop
              install -Dm644 ${openresearchContents}/usr/share/icons/hicolor/256x256/apps/OpenResearch.png \
                $out/share/icons/hicolor/256x256/apps/OpenResearch.png
            '';
            meta = {
              description = "OpenResearch desktop for automated ML research";
              homepage = "https://openresearch.sh/";
              platforms = [ "x86_64-linux" ];
            };
          }
        );
        orx =
          pkgs.runCommand "orx-${openresearchVersion}"
            {
              nativeBuildInputs = [ pkgs.xz ];
              meta = {
                description = "OpenResearch CLI (orx) for automated ML research";
                homepage = "https://openresearch.sh/";
                platforms = [ "x86_64-linux" ];
              };
            }
            ''
              mkdir orx
              tar -xJf ${
                pkgs.fetchurl {
                  url = "https://github.com/alphaXiv/OpenResearch/releases/download/v${openresearchVersion}/openresearch-cli-x86_64-unknown-linux-musl.tar.xz";
                  hash = "sha256-fkc8ILTJa/pDxgRG/w9l47L05XKY1isL/X2/JlfiC7Y=";
                }
              } -C orx
              install -Dm755 orx/openresearch-cli-x86_64-unknown-linux-musl/orx $out/bin/orx
            '';
        # Eigent is an open-source multi-agent workforce desktop app whose
        # Linux distribution is only an AppImage. Extract the squashfs
        # offline and run its AppRun through
        # appimage-exec.sh inside a buildFHSEnv chroot. The ~700 MB payload
        # is mostly the bundled terminal runtime (resources/prebuilt: uv,
        # bun, a full cpython-3.10.19 and a terminal venv) which the app
        # provisions into $HOME at first run. The app also rewrites
        # resources/prebuilt/terminal_venv/pyvenv.cfg and drops a
        # .terminal_venv_fixed marker beside it at every startup, and its
        # dependency check hard-fails on EROFS (the UI then hangs on
        # "starting up"), so it must run from a writable mirror of the
        # unpacked tree (eigentRun below), never straight from the store.
        eigentVersion = "1.0.6";
        # v1.0.6 publishes the AppImage on GitHub releases, so a plain
        # fetchurl replaces the old eigent.ai requireFile manual download.
        eigentAppImage = pkgs.fetchurl {
          name = "Eigent-1.0.6.AppImage";
          url = "https://github.com/eigent-ai/eigent/releases/download/v1.0.6/Eigent-1.0.6.AppImage";
          hash = "sha256-+Hzwvrd3GCHlnlCyUpvBg5g8pQfHOIECKwzCMrNgkMU=";
        };
        eigentUnpacked =
          pkgs.runCommand "eigent-${eigentVersion}-unpacked"
            {
              nativeBuildInputs = [ pkgs.squashfsTools ];
            }
            ''
              # The first hsqs match sits
              # inside the runtime ELF, so keep offsets until one validates as a
              # real superblock and yields the app tree.
              extracted=
              for offset in $(grep -abo 'hsqs' ${eigentAppImage} | cut -d: -f1); do
                rm -rf root
                if unsquashfs -q -n -o "$offset" -d root ${eigentAppImage} >/dev/null 2>&1 && [ -x root/AppRun ]; then
                  extracted=1
                  break
                fi
              done
              if [ -z "$extracted" ]; then
                echo "eigent: no valid squashfs superblock found in the AppImage" >&2
                exit 1
              fi
              mv root $out
            '';
        # The store tree is read-only, but the app writes into its own
        # resources/prebuilt at startup (see comment above). Mirror the
        # unpacked tree into ~/.local/share/eigent-app once and run from
        # there; refresh the mirror when the package version changes.
        eigentRun = pkgs.writeShellScript "eigent-run" ''
          APP_HOME="''${XDG_DATA_HOME:-$HOME/.local/share}/eigent-app"
          STAMP="$APP_HOME/.nix-eigent-stamp"
          if ! [ -x "$APP_HOME/AppRun" ] || ! [ "$(cat "$STAMP" 2>/dev/null)" = "${eigentVersion}" ]; then
            ${pkgs.coreutils}/bin/rm -rf "$APP_HOME"
            ${pkgs.coreutils}/bin/mkdir -p "$APP_HOME"
            ${pkgs.coreutils}/bin/cp -a "${eigentUnpacked}/." "$APP_HOME/"
            ${pkgs.coreutils}/bin/chmod -R u+w "$APP_HOME"
            ${pkgs.coreutils}/bin/printf '%s\n' "${eigentVersion}" > "$STAMP"
          fi
          exec appimage-exec.sh -w "$APP_HOME" -- --no-sandbox "$@"
        '';
        eigentDesktopItem = pkgs.makeDesktopItem {
          name = "eigent";
          desktopName = "Eigent";
          comment = "Eigent multi-agent workforce desktop";
          exec = "${config.home.profileDirectory}/bin/eigent %U";
          icon = "eigent";
          # Upstream registers the eigent:// deep link.
          mimeTypes = [ "x-scheme-handler/eigent" ];
          categories = [ "Development" ];
          startupNotify = true;
          startupWMClass = "Eigent";
        };
        eigent = pkgs.buildFHSEnv (
          pkgs.appimageTools.defaultFhsEnvArgs
          // {
            name = "eigent";
            # Upstream's desktop entry execs `AppRun --no-sandbox %U`, so
            # pass the flag the same way (NixOS chrome-sandbox is not
            # setuid-root either).
            runScript = "${eigentRun}";
            targetPkgs =
              p:
              [ pkgs.appimageTools.appimage-exec ]
              ++ pkgs.appimageTools.defaultFhsEnvArgs.targetPkgs p
              ++ (with p; [
                libsecret
                # The AppRun updater prompts through zenity when present and
                # skips silently otherwise.
                zenity
              ]);
            extraInstallCommands = ''
              install -Dm644 ${eigentDesktopItem}/share/applications/eigent.desktop $out/share/applications/eigent.desktop
              # Upstream ships a single top-level eigent.png (the 0x0
              # hicolor dir it also has is unusable).
              install -Dm644 ${eigentUnpacked}/eigent.png $out/share/icons/hicolor/512x512/apps/eigent.png
            '';
            meta = {
              description = "Eigent multi-agent workforce desktop";
              homepage = "https://eigent.ai/";
              platforms = [ "x86_64-linux" ];
            };
          }
        );
        # Grok Bot desktop agent (electron-builder .deb, the Cursor "sand"
        # agent rebranded). Same FHS-env treatment as the eigent AppImage:
        # extract the deb and run the electron binary directly. The deb
        # layout lives under /opt on regular distros (root-owned), so the
        # app is not written to write into its resources and needs no
        # writable mirror. NixOS's chrome-sandbox is not setuid-root either,
        # so pass --no-sandbox like upstream's own desktop entry.
        grokBotVersion = "0.71.2";
        grokBotDeb = pkgs.requireFile {
          name = "grok-bot_${grokBotVersion}_amd64.deb";
          sha256 = "0j33n15b166avvl2qqs3s2l8albamb1rp207wmcyslp8ldsnslm0";
          message = ''
            Copy grok-bot_${grokBotVersion}_amd64.deb into ~/Downloads so it
            can be imported into the nix store.
          '';
        };
        grokBotUnpacked = pkgs.runCommand "grok-bot-${grokBotVersion}-unpacked" { } ''
          ${pkgs.dpkg}/bin/dpkg-deb -x ${grokBotDeb} $out
        '';
        grokBotDesktopItem = pkgs.makeDesktopItem {
          name = "grok-bot";
          desktopName = "Grok Bot";
          comment = "Grok Bot desktop agent";
          exec = "${config.home.profileDirectory}/bin/grok-bot %U";
          icon = "grok-bot";
          # Upstream registers grokbot:// and the legacy sand:// deep link.
          mimeTypes = [
            "x-scheme-handler/grokbot"
            "x-scheme-handler/sand"
          ];
          categories = [ "Development" ];
          startupNotify = true;
          startupWMClass = "grok-bot";
        };
        grokBot = pkgs.buildFHSEnv (
          pkgs.appimageTools.defaultFhsEnvArgs
          // {
            name = "grok-bot";
            runScript = "${pkgs.writeShellScript "grok-bot-run" ''
              exec "${grokBotUnpacked}/opt/Grok Bot/grok-bot" --no-sandbox "$@"
            ''}";
            targetPkgs =
              p:
              pkgs.appimageTools.defaultFhsEnvArgs.targetPkgs p
              ++ (with p; [
                libsecret
                xdg-utils
              ]);
            extraInstallCommands = ''
              install -Dm644 ${grokBotDesktopItem}/share/applications/grok-bot.desktop $out/share/applications/grok-bot.desktop
              # The deb ships a complete hicolor set for grok-bot.
              ${pkgs.coreutils}/bin/mkdir -p $out/share/icons
              ${pkgs.coreutils}/bin/cp -r --no-preserve=mode ${grokBotUnpacked}/usr/share/icons/hicolor $out/share/icons/hicolor
            '';
            meta = {
              description = "Grok Bot desktop agent";
              platforms = [ "x86_64-linux" ];
            };
          }
        );
        # DeepSeek Harness CLI. The official npm package is the scoped
        # @deepseek-ai/dsh; the unscoped `deepseek-harness` name is a
        # reserved 0.0.1 placeholder with no bin, which hung `pnpm dlx`.
        # Built with buildNpmPackage instead of a runtime dlx: the registry
        # tarball ships no lockfile, so dsh-package-lock.json is generated
        # with `npm install --package-lock-only` and committed; regenerate it
        # (and refresh npmDepsHash) on every version bump. --ignore-scripts:
        # every native dep ships prebuilds (node-pty, koffi, sharp via
        # @img/*, sherpa-onnx); the one meaningful postinstall
        # (dsh-subprocess-local) only chmods node-pty's bundled
        # spawn-helper, replicated in postInstall. This derivation only
        # provides the node_modules tree; the runnable `dsh` is
        # deepseekHarnessCli below, which runs it on the official Node.
        deepseekHarness = pkgs.buildNpmPackage rec {
          pname = "deepseek-harness";
          version = "0.2.1-rc.2";
          src = pkgs.fetchurl {
            url = "https://registry.npmjs.org/@deepseek-ai/dsh/-/dsh-${version}.tgz";
            hash = "sha256-QOPQJcAkDEMW/0Le6b7cdwnA+ziuoQVDtHB27Sr1Lh0=";
          };
          sourceRoot = "package";
          postPatch = "cp ${./dsh-package-lock.json} package-lock.json";
          npmFlags = [ "--ignore-scripts" ];
          dontNpmBuild = true;
          npmDepsHash = "sha256-njzlHReorgm1RzEwMYwzx6OegKKWGVQtV6OiN9nxriE=";
          postInstall = ''
            # Restore node-pty's bundled spawn-helper exec bit, as
            # dsh-subprocess-local's skipped postinstall would have.
            find "$out" -path "*node-pty/prebuilds*" -name spawn-helper -type f -exec chmod 755 {} +
          '';
          meta = {
            description = "DeepSeek Harness CLI: profiles, plugins, and agent runtime";
            homepage = "https://www.npmjs.com/package/@deepseek-ai/dsh";
            license = lib.licenses.mit;
            mainProgram = "dsh";
            platforms = [ "x86_64-linux" ];
          };
        };
        # dsh's runtime-interception addon (node-addon-require-builtin)
        # obtains Node's internal requireBuiltin by probing private V8 state
        # and pattern-matching the OFFICIAL nodejs.org build's machine code;
        # on nixpkgs' gcc-built node it fails closed at boot with
        # "Unsupported/no-getter". dsh therefore runs on the official
        # binary through the host's nix-ld (see deepseekHarnessCli below).
        # Keep this on a major the addon supports (20/22/24/26).
        dshNodeVersion = "24.22.1";
        dshNode =
          pkgs.runCommand "nodejs-official-${dshNodeVersion}"
            {
              nativeBuildInputs = [ pkgs.xz ];
            }
            ''
              mkdir -p $out
              tar -xJf ${
                pkgs.fetchurl {
                  url = "https://nodejs.org/dist/v${dshNodeVersion}/node-v${dshNodeVersion}-linux-x64.tar.xz";
                  hash = "sha256-bBcqmrZxj3uAH7WnvUhq8u5eMnWAhqBLhPzOKqdwleY=";
                }
              } --strip-components=1 -C $out
            '';
        # dsh-market shells out to a bare `pnpm` for plugin lookups
        # (`pnpm view <plugin> ... --json`) and installs, but the official
        # node tarball ships no pnpm. Pin the same pnpm dsh-market's own
        # runtime uses (11.25.0, store v11) and run it on the official node;
        # the pure-JS registry tarball works on any node build.
        dshPnpmPkg = pkgs.runCommand "pnpm-11.25.0-pkg" { } ''
          mkdir -p $out
          tar -xzf ${
            pkgs.fetchurl {
              url = "https://registry.npmjs.org/pnpm/-/pnpm-11.25.0.tgz";
              hash = "sha256-M90HSPJ+eRbE8ci2lDRhmD40U7BrvaYxKmKAEwtIgeU=";
            }
          } -C $out --strip-components=1
        '';
        dshPnpm = pkgs.writeShellScriptBin "pnpm" ''
          exec ${dshNode}/bin/node ${dshPnpmPkg}/bin/pnpm.cjs "$@"
        '';
        # Official node first on PATH so child processes dsh spawns (npm,
        # plugin tooling, re-execs) resolve the same runtime. Runs through
        # the host's nix-ld, NOT a buildFHSEnv: inside bwrap, dsh's harness
        # child falls back to dsh-market's standalone pnpm, whose embedded
        # (non-official) node fails the interception addon; under nix-ld the
        # child inherits this node and boots. See hermes-desktop.nix for the
        # same programs.nix-ld requirement.
        # Keep bubblewrap reachable on PATH: Codex's app-server (the
        # dsh-openai-oauth plugin's backend) shells out to `bwrap` for its
        # sandbox and logs an ERROR on every start when PATH lacks it, falling
        # back to the copy vendored in the Codex binary.
        # CloudFront in front of platform.deepseek.com (BLR edge) rejects any
        # request whose User-Agent is not a full browser string: node, undici,
        # curl and even a bare "Mozilla/5.0" all get a 403 "Request blocked"
        # HTML page, which dsh-deepseek-account-platform logs as
        # `[deepseek-account] request failed ... errorCode: 'network'`. The
        # account client sends no User-Agent of its own, so undici's default
        # `node` is what the edge sees. api.deepseek.com is exempt, which is
        # why model listing still succeeds. Only set it when unset, so an
        # explicit override in the environment still wins.
        deepseekHarnessCli = pkgs.writeShellScriptBin "dsh" ''
          export PATH="${dshPnpm}/bin:${dshNode}/bin:${pkgs.bubblewrap}/bin''${PATH:+:$PATH}"
          if [ -z "''${DSH_PLATFORM_USER_AGENT:-}" ]; then
            export DSH_PLATFORM_USER_AGENT="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
          fi
          exec ${dshNode}/bin/node --require ${./dsh-platform-ua.cjs} ${deepseekHarness}/lib/node_modules/@deepseek-ai/dsh/lib/bin.js "$@"
        '';
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
        # Feynman is an end-to-end coding agent CLI. Two separate
        # distributions exist: `feynman-coding-agent` is the standalone CLI
        # published as a pnpm-run bundle, while `@companion-ai/feynman` is the
        # Pi-based agent that also ships a Pi extension/prompts/skills bundle
        # (installed through piPackages in piModule).
        feynman = pkgs.writeShellScriptBin "feynman" ''
          exec ${pkgs.pnpm}/bin/pnpm dlx --package feynman-coding-agent@latest feynman "$@"
        '';
        # The Pi-based Feynman distribution, same pnpm-run shape and pinned to
        # the package the piPackages entry installs so the CLI and the Pi
        # extension stay on one version.
        feynmanPi = pkgs.writeShellScriptBin "feynman-pi" ''
          exec ${pkgs.pnpm}/bin/pnpm dlx --package @companion-ai/feynman@latest feynman "$@"
        '';
        # Grok Build (grok.com/build) is xAI's terminal coding agent. The
        # npm wrapper @xai-official/grok resolves a platform package whose
        # bin/grok.br brotli-decompresses into a statically linked Rust
        # binary, so it runs on NixOS without an FHS env or interpreter
        # patching. Resolved through pnpm like the other agent CLIs.
        grok = pkgs.writeShellScriptBin "grok" ''
          exec ${pkgs.pnpm}/bin/pnpm dlx --package @xai-official/grok@latest grok "$@"
        '';
        # Official Claude Desktop. Launcher name is "Claude". The `claude`
        # CLI stays the separate nixpkgs package.
        claudeDesktop = pkgs.callPackage ./claude-desktop.nix { };

      in
      {
        imports = [ piModule ];

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

        # OpenResearch only rewrites its desktop entry in AppImage mode (the
        # unset APPIMAGE above prevents that), but an entry it wrote during a
        # manual upstream AppImage run would shadow the profile's entry via
        # XDG_DATA_HOME and point at the store AppImage. force = true
        # overwrites any such stale file instead of aborting activation.
        xdg.dataFile."applications/openresearch.desktop" = {
          source = "${openresearchDesktopItem}/share/applications/openresearch.desktop";
          force = true;
        };

        # Searched before the profile. Keeps a file the app wrote on a
        # previous run from hiding this entry.
        xdg.dataFile."applications/com.anthropic.Claude.desktop" = {
          source = "${claudeDesktop}/share/applications/com.anthropic.Claude.desktop";
          force = true;
        };

        home.packages = with pkgs; [
          superfile
          wget
          git
          gh
          jujutsu
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
          deepseekHarnessCli
          qmd
          agentBrowser
          feynman
          feynmanPi
          grok
          # nixpkgs package; the command is `claude`. It tracks the flake pin.
          claude-code
          claudeDesktop
          zcode
          eigent
          openresearch
          orx
          grokBot
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

        programs.jujutsu = {
          enable = true;
          settings = {
            user.name = "Surya Vamsi";
            user.email = "d.suryavamsi@gmail.com";
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
        home.packages = [
          pkgs.gh
          pkgs.jujutsu
        ];

        programs.nh = {
          enable = true;
          flake = "/Users/suryavamsi/Dotfiles/nixos-config";
        };

        programs.git = {
          enable = true;
          settings.user.name = "Surya Vamsi";
          settings.user.email = "d.suryavamsi@gmail.com";
        };

        programs.jujutsu = {
          enable = true;
          settings = {
            user.name = "Surya Vamsi";
            user.email = "d.suryavamsi@gmail.com";
          };
        };
      };
  };
}
