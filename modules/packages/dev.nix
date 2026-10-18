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
        # T3 Code (t3.codes) is not pinned by this flake: it is nixpkgs'
        # `pkgs.t3code`, which is still 0.0.45. Upstream shipped stable v0.1.0
        # after the locked nixpkgs revision, and the nixpkgs bump PR
        # (NixOS/nixpkgs#575132) is open but unmerged, so bump it here instead.
        # Both hashes come from NixOS/nixpkgs#575132: the fetchFromGitHub tree
        # hash and the fetchPnpmDeps output hash. Drop this override once the
        # bump reaches the pinned nixpkgs.
        t3code = pkgs.t3code.override {
          t3code-unwrapped =
            (pkgs.callPackage "${pkgs.path}/pkgs/by-name/t3/t3code/unwrapped.nix" { }).overrideAttrs
              (old: {
                version = "0.1.0";
                src = pkgs.fetchFromGitHub {
                  owner = "pingdotgg";
                  repo = "t3code";
                  tag = "v0.1.0";
                  hash = "sha256-P82DqoY1E9wtROwu5Nr7MB/I1PdmZHWXXR4nRa4GWXM=";
                };
                pnpmDeps = old.pnpmDeps.overrideAttrs (_: {
                  outputHash = "sha256-oX4tOu20tYO3ci7VvSEL8eFgxAYWp5HlQFSfAWJGJmg=";
                });
              });
        };
        ohMyPi = pkgs.stdenvNoCC.mkDerivation {
          pname = "oh-my-pi";
          version = "18.12.0";
          src = pkgs.fetchurl {
            url = "https://github.com/can1357/oh-my-pi/releases/download/v18.12.0/omp-linux-x64";
            hash = "sha256-RMkhA3J50FcjkMBaEfNgjnZCLZaudyM74Q+x5j4vSH8=";
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
          version = "1.4.229";
          src = pkgs.fetchurl {
            url = "https://github.com/stablyai/orca/releases/download/v1.4.229/orca-linux.AppImage";
            hash = "sha256-Az6Uflnd9PZrdRiIJX3XmPiDRttzCvGG/slKblUdfaA=";
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
          version = "1.2.8";
          src = pkgs.fetchurl {
            url = "https://github.com/generalaction/emdash/releases/download/v1.2.8/emdash-x86_64.AppImage";
            hash = "sha256-zYlzjgu8zICn+/AJ3eyyvRuMb9hYsU11seTHwfLu5/U=";
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
        zcodeVersion = "3.15.3";
        zcodeSrc = pkgs.fetchurl {
          url = "https://cdn-zcode.z.ai/zcode/electron/releases/${zcodeVersion}/linux-x64/ZCode-${zcodeVersion}-linux-x64.AppImage";
          hash = "sha256-Ltx5ZQ/P9yNYZwr0/7+/fZebqVR2YRqArRFR1XfpD+M=";
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
        # bundled agent runtime. Since 2.x Linux ships only as an AppImage,
        # and its custom runtime ignores --appimage-extract (running it
        # self-installs into ~/.cache/appimage-run instead), unpack it
        # offline: a type-2 AppImage is an ELF runtime with a squashfs
        # appended, so unsquashfs can read the tree straight from the
        # superblock offset without executing anything. The tree then runs
        # inside the same FHS environment the AppImage apps above get from
        # appimageTools' defaults — Electron's interpreter/loader
        # expectations are the same problem wrapType2 solves for them. The
        # zwork runtime is pre-extracted under resources/app/vendor (bun,
        # dotnet, node, ripgrep), so nothing needs the deb-era gateway.tar
        # unpack. Linux builds are x86_64-only.
        autoclawVersion = "2.0.3";
        # The update channel serves the in-app updater, not a stable URL, so
        # the AppImage stays a manual download. Pure flake eval cannot read
        # ~/Downloads, so resolve it from the store via requireFile: after
        # downloading, run once (and again for every new version, updating
        # name/sha256 here):
        #   nix-store --add-fixed sha256 ~/Downloads/AutoClaw-2.0.3-x64.AppImage
        autoclawAppImage = pkgs.requireFile {
          name = "AutoClaw-2.0.3-x64.AppImage";
          sha256 = "1v5bwcxp5jxaakq2xs1bgd8n843sxwzj56yrgvip06fr3rabjqy6";
          url = "https://autoclaw.z.ai/";
        };
        autoclawUnpacked = pkgs.runCommand "autoclaw-${autoclawVersion}-unpacked" {
          nativeBuildInputs = [ pkgs.squashfsTools ];
        } ''
          # The magic scan can hit false matches inside the runtime ELF, so
          # try each occurrence until one validates as a real superblock and
          # yields the app tree.
          extracted=
          for offset in $(grep -abo 'hsqs' ${autoclawAppImage} | cut -d: -f1); do
            rm -rf root
            if unsquashfs -q -n -o "$offset" -d root ${autoclawAppImage} >/dev/null 2>&1 && [ -x root/AppRun ]; then
              extracted=1
              break
            fi
          done
          if [ -z "$extracted" ]; then
            echo "autoclaw: no valid squashfs superblock found in the AppImage" >&2
            exit 1
          fi
          mv root $out
        '';
        autoclawDesktopItem = pkgs.makeDesktopItem {
          name = "autoclaw";
          desktopName = "AutoClaw";
          comment = "AutoClaw desktop AI product";
          exec = "${config.home.profileDirectory}/bin/autoclaw %U";
          icon = "autoclaw";
          # Upstream registers the zwork:// deep link; the handler exists as
          # soon as this desktop file lands in the profile.
          mimeTypes = [ "x-scheme-handler/zwork" ];
          categories = [ "Utility" ];
          startupNotify = true;
          startupWMClass = "AutoClaw";
        };
        autoclaw = pkgs.buildFHSEnv (
          pkgs.appimageTools.defaultFhsEnvArgs
          // {
            name = "autoclaw";
            # What wrapType2 runs: appimage-exec.sh -w execs the AppRun of
            # the extracted tree with APPDIR set; AppRun itself probes user
            # namespaces and passes --no-sandbox to Electron when they are
            # unavailable.
            runScript = "appimage-exec.sh -w ${autoclawUnpacked} --";
            # libsecret for the keyring. nss, libxtst, xdg-utils, at-spi and
            # libnotify are already in the default chroot list.
            targetPkgs =
              p:
              [ pkgs.appimageTools.appimage-exec ]
              ++ pkgs.appimageTools.defaultFhsEnvArgs.targetPkgs p
              ++ (with p; [ libsecret ]);
            extraInstallCommands = ''
              install -Dm644 ${autoclawDesktopItem}/share/applications/autoclaw.desktop $out/share/applications/autoclaw.desktop
              # 2.x ships a single 512x512 icon named after the AutoClaw2 binary.
              install -Dm644 ${autoclawUnpacked}/usr/share/icons/hicolor/512x512/apps/AutoClaw2.png \
                $out/share/icons/hicolor/512x512/apps/autoclaw.png
            '';
            meta = {
              description = "AutoClaw desktop AI product";
              homepage = "https://autoclaw.z.ai/";
              platforms = [ "x86_64-linux" ];
            };
          }
        );
        # OpenResearch (openresearch.sh, alphaXiv) is an agentic ML research
        # desktop whose Linux build is an AppImage wrapping an `orx` GUI
        # (AppRun ignores argv and always launches `orx app`). The bundled
        # binary wants /lib64/ld-linux-x86-64.so.2 — NixOS' stub-ld here — so
        # the extracted tree runs in a buildFHSEnv, like zcode/autoclaw. The
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
              p:
              [ pkgs.appimageTools.appimage-exec ]
              ++ pkgs.appimageTools.defaultFhsEnvArgs.targetPkgs p;
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
        orx = pkgs.runCommand "orx-${openresearchVersion}" {
          nativeBuildInputs = [ pkgs.xz ];
          meta = {
            description = "OpenResearch CLI (orx) for automated ML research";
            homepage = "https://openresearch.sh/";
            platforms = [ "x86_64-linux" ];
          };
        } ''
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
        # Linux distribution is only an AppImage. Reuse the AutoClaw
        # approach: extract the squashfs offline and run its AppRun through
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
        eigentUnpacked = pkgs.runCommand "eigent-${eigentVersion}-unpacked" {
          nativeBuildInputs = [ pkgs.squashfsTools ];
        } ''
          # Same magic-scan dance as autoclaw: the first hsqs match sits
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
          mimeTypes = [ "x-scheme-handler/grokbot" "x-scheme-handler/sand" ];
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
        # because the package's plugin bundles use peer dependencies. Install
        # the OAuth provider into the persistent web profile on first launch.
        deepseekHarness = pkgs.writeShellScriptBin "deepseek-harness" ''
          export XDG_DATA_HOME="''${XDG_DATA_HOME:-$HOME/.local/share}/deepseek-harness"
          export NODE_PATH="${pkgs.pnpm}/lib/node_modules"
          exec ${pkgs.pnpm}/bin/pnpm dlx --package deepseek-harness@latest deepseek-harness "$@"
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

        # AutoClaw 2.x keeps its settings in the profile the app derives from
        # its build flavor — ~/.config/AutoClaw-oversea-official for this
        # official/overseas build, not the mainland build's
        # ~/.config/autoclaw. Pin the app's own settings file to en-US; with
        # the app running the file can be rewritten from memory, hence an
        # activation rather than a one-off edit. Drop this block to let the
        # in-app Settings → Appearance choice win instead.
        home.activation.autoclawLanguage = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          autoclawSettings="$HOME/.config/AutoClaw-oversea-official/settings.json"
          if [ -f "$autoclawSettings" ]; then
            if ${pkgs.jq}/bin/jq '.appearance.language = "en-US"' "$autoclawSettings" > "$autoclawSettings.new"; then
              mv "$autoclawSettings.new" "$autoclawSettings"
            fi
            rm -f "$autoclawSettings.new"
          else
            # Seed a fresh profile so the first launch is English too; the
            # app fills in its remaining defaults on start.
            mkdir -p "$HOME/.config/AutoClaw-oversea-official"
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

        # OpenResearch only rewrites its desktop entry in AppImage mode (the
        # unset APPIMAGE above prevents that), but an entry it wrote during a
        # manual upstream AppImage run would shadow the profile's entry via
        # XDG_DATA_HOME and point at the store AppImage. force = true
        # overwrites any such stale file instead of aborting activation.
        xdg.dataFile."applications/openresearch.desktop" = {
          source = "${openresearchDesktopItem}/share/applications/openresearch.desktop";
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
          deepseekHarness
          qmd
          agentBrowser
          feynman
          feynmanPi
          grok
          emdash
          zcode
          autoclaw
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
