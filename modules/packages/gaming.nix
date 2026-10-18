# Gaming packages (NixOS)
{ lib, ... }:
{
  options.flake.modules.nixos.gaming = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { pkgs, ... }:
      let
        # `libgamemodeauto.so.0` is the LD_PRELOAD shim `gamemoderun` installs.
        # It dlopens the real library (`libgamemode.so.0`, falling back to
        # `libgamemode.so`), but nixpkgs only gives an rpath to `gamemoded` and
        # `gamemode-simulate-game` (pkgs/by-name/ga/gamemode/package.nix). The shim
        # instead leaned on the wrapper's `LD_LIBRARY_PATH`, which Steam discards:
        # inside its pressure-vessel container the runtime rewrites `LD_PRELOAD` to
        # a captured copy of the shim and replaces `LD_LIBRARY_PATH` with its own
        # override dirs, so the dlopen fails with
        # `gamemodeauto: dlopen failed - libgamemode.so: cannot open shared object
        # file` in every process of the game tree, and those processes miss
        # GameMode's scheduling changes. `/nix/store` stays visible inside that
        # container, so an rpath to the shim's own lib dir resolves it in both.
        patchShim = gamemode: gamemode.overrideAttrs (old: {
          postFixup = (old.postFixup or "") + ''
            # Prepend the shim's own directory, keeping the rpath nixpkgs set
            # for the NEEDED libs (glibc), so the dlopen resolves next to
            # whichever copy was actually loaded.
            for f in "$lib"/lib/libgamemodeauto.so.*.*; do
              [ -f "$f" ] && [ ! -L "$f" ] || continue
              rpath="$(patchelf --print-rpath "$f")"
              case ":$rpath:" in
                *":$lib/lib:"*) ;;
                *) patchelf --set-rpath "$lib/lib''${rpath:+:$rpath}" "$f" ;;
              esac
            done
          '';
        });

        # `gamemoderun` hardcodes the 32-bit library path for 32-bit apps, and
        # that reference is how the 32-bit shim reaches the Steam FHS environment,
        # so the wrapper has to be rebuilt to point at a patched 32-bit copy.
        gamemodePatched = patchShim (pkgs.gamemode.override {
          pkgsi686Linux = pkgs.pkgsi686Linux // {
            gamemode = patchShim pkgs.pkgsi686Linux.gamemode;
          };
        });

        # Steam keys a compat tool by the name written in its
        # `compatibilitytool.vdf`, but the tool list it scans — and therefore both
        # the Properties → Compatibility dropdown and the `CompatToolMapping`
        # string Steam persists — is keyed by the *directory* name, which nixpkgs
        # derives from the release (`GE-Proton11-7`). nixpkgs' `proton-ge-bin`
        # deliberately collapses every release onto the internal name "GE-Proton"
        # (`steamDisplayName`), so the two names disagree and a second installed
        # release also collides on that one name. When they disagree, picking the
        # tool stores a name Steam cannot resolve; the per-app mapping then falls
        # back to the `native` tool, Steam drops the compat wrapper, and the game's
        # `.exe` is exec'd directly on Linux with
        #   REDprelauncher.exe: cannot execute binary file
        # (The Witcher 3, observed 2026-10-02.) Naming each release after itself
        # keeps the registry name, the directory name and the mapping string equal.
        protonGeBin = pkgs.proton-ge-bin.overrideAttrs (old: {
          steamDisplayName = old.version;
        });
        # The official Epic Games Launcher — the Tauri-based rework ("preview");
        # the classic launcher never shipped for Linux — distributes an AppImage
        # that bundles WebKitGTK 4.1, GStreamer, gnutls (its GIO TLS module)
        # and libsecret, so the extracted tree runs in a buildFHSEnv like
        # openresearch (binary interpreter is
        # /lib64/ld-linux-x86-64.so.2 = NixOS' stub-ld). Epic serves the file
        # only through the Cloudflare-fronted store page with no versioned
        # URL, so requireFile pins the manually downloaded AppImage; after
        # fetching a new build from
        # https://store.epicgames.com/en-US/install/ng/ (and bumping the hash),
        # re-satisfy the build with
        #   nix-store --add-fixed sha256 ~/Downloads/EpicGamesLauncher-x86_64.AppImage
        # The runScript must unset APPIMAGE: the launcher keys its AppImage
        # self-updater (rename + relaunch of the running AppImage) on that
        # variable, and with it set it treats itself as a self-updating
        # AppImage instead of a flake-managed build.
        epicLauncherAppImage = pkgs.requireFile {
          name = "EpicGamesLauncher-x86_64.AppImage";
          url = "https://store.epicgames.com/en-US/install/ng/";
          hash = "sha256-wp0ccwRNhmJxkTcWUhTpaWtp/QJB90JrHjHSXVp2mW8=";
        };
        epicLauncherContents = pkgs.appimageTools.extract {
          pname = "epicgameslauncher";
          version = "0.95.1";
          src = epicLauncherAppImage;
        };
        epicLauncherRun = pkgs.writeShellScript "epicgameslauncher-run" ''
          # See above: APPIMAGE flips the launcher into AppImage self-update mode.
          unset APPIMAGE
          exec appimage-exec.sh -w ${epicLauncherContents} -- "$@"
        '';
        epicgameslauncher = pkgs.buildFHSEnv (
          pkgs.appimageTools.defaultFhsEnvArgs
          // {
            name = "epicgameslauncher";
            runScript = "${epicLauncherRun}";
            targetPkgs =
              p:
              [ pkgs.appimageTools.appimage-exec ]
              ++ pkgs.appimageTools.defaultFhsEnvArgs.targetPkgs p;
            # Ship the bundled entry (it carries the com.epicgames.launcher
            # deep-link handler) with Exec pointed at the wrapper; the
            # AppRun GTK hook forces GDK_BACKEND=x11 (Tauri's Wayland backend
            # crashes — tauri#8541) and wires schemas/typelibs into the bundle.
            extraInstallCommands = ''
              install -Dm644 ${epicLauncherContents}/usr/share/applications/epic-games-launcher.desktop \
                $out/share/applications/epic-games-launcher.desktop
              substituteInPlace $out/share/applications/epic-games-launcher.desktop \
                --replace "Exec=EpicGamesLauncher" "Exec=epicgameslauncher"
              for size in 32x32 128x128 256x256@2; do
                install -Dm644 ${epicLauncherContents}/usr/share/icons/hicolor/$size/apps/EpicGamesLauncher.png \
                  $out/share/icons/hicolor/$size/apps/EpicGamesLauncher.png
              done
            '';
            meta = {
              description = "Epic Games Launcher (Linux preview)";
              homepage = "https://store.epicgames.com/en-US/install/ng/";
              platforms = [ "x86_64-linux" ];
              license = lib.licenses.unfree;
            };
          }
        );
      in
      {
        # HTTP/2 is disabled in the Steam client through the user config below.
        environment.systemPackages = with pkgs; [
          gamescope
          protonup-ng
          mangohud
          # Qt front-end for MangoHud's config file; the overlay itself comes
          # from `mangohud` above.
          goverlay
          trigger-control
          wine
          heroic
          bottles
          epicgameslauncher
          qbittorrent
          mangojuice
        ];
        services.flatpak = {
          remotes = [
            {
              name = "flathub";
              location = "https://dl.flathub.org/repo/flathub.flatpakrepo";
            }
            {
              name = "amethyst";
              location = "https://chrisdkn.github.io/Amethyst-Mod-Manager/amethyst.flatpakrepo";
            }
          ];
          packages = [
            {
              appId = "io.github.Amethyst.ModManager";
              origin = "amethyst";
            }
          ];
        };

        # GameMode's helpers run as root through pkexec, but its own polkit
        # policy ships `<allow_any>no</allow_any><allow_inactive>no</allow_inactive>
        # <allow_active>no</allow_active>` for every action, so polkit denies
        # outright and no authentication agent can help — `gamemoded` logs
        # `pkexec ... cpugovctl set performance: Not authorized` in every session,
        # Game Mode or desktop. NixOS ships no rule for it either. This grants
        # the two CPU helpers to active local `wheel` users, which is what other
        # distributions do; the GPU and /proc/sys helpers stay denied and are
        # unused here.
        security.polkit.extraConfig = ''
          polkit.addRule(function(action, subject) {
            if ((action.id == "com.feralinteractive.GameMode.governor-helper" ||
                 action.id == "com.feralinteractive.GameMode.cpu-helper") &&
                subject.isInGroup("wheel") &&
                subject.local &&
                subject.active) {
              return polkit.Result.YES;
            }
          });
        '';

        programs = {
          gamemode = {
            enable = true;
            settings = {
              general = {
                renice = 0;
                inhibit_screensaver = 1;
              };
              cpu = {
                park_cores = 0;
                pin_cores = 0;
              };
              # Stop compositor idle/DPMS handling for the duration of a GameMode session.
              # The MangoWM profile uses mango-idle; the Hyprland profile uses hypridle.
              custom = {
                start = "${pkgs.systemd}/bin/systemctl --user stop hypridle.service mango-idle.service || true";
                end = "${pkgs.systemd}/bin/systemctl --user start hypridle.service mango-idle.service || true";
                script_timeout = 10;
              };
            };
          };
          steam = {
            enable = true;
            # Bare nixpkgs session, kept for hosts that do not import
            # nixos.gamingMode (`#nixos` replaces it with a configured
            # SteamOS-style entry, see modules/desktop/gaming-mode.nix).
            gamescopeSession.enable = true;
            extraCompatPackages = [
              pkgs.proton-cachyos
              protonGeBin
            ];
            package = pkgs.steam.override {
              extraPkgs = (
                pkgs: with pkgs; [
                  gamemodePatched
                  mangohud
                  # Wine's Media Foundation bridge needs these for H.264 game videos.
                  gst_all_1.gstreamer
                  gst_all_1.gst-plugins-base
                  gst_all_1.gst-plugins-good
                  gst_all_1.gst-plugins-bad
                  gst_all_1.gst-plugins-ugly
                  gst_all_1.gst-libav
                ]
              );
              # `MANGOHUD=1` is what the Vulkan layer's `enable_environment`
              # (`MangoHud.x86_64.json`) gates on, so it is also what makes the
              # per-game `MANGOHUD_CONFIGFILE` launch options take effect — in
              # Game Mode too, where gamescope's --mangoapp reads that same
              # config file for its own overlay.
              extraProfile = ''
                export MANGOHUD=1
              '';
            };
          };
        };
      };
  };

  options.flake.modules.homeManager.gaming = lib.mkOption {
    type = lib.types.deferredModule;
    default = { pkgs, ... }: {
      # Must run as the user; a global user-tmpfiles rule also runs for greetd.
      home.file.".local/share/Steam/steam_dev.cfg".source = pkgs.writeText "steam_dev.cfg" ''
        @nClientDownloadEnableHTTP2PlatformLinux 0
      '';
      programs.mangohud = {
        enable = true;
        settings = {
          # Default profile for multiplayer games: lower-latency late limiter.
          fps_limit = 170;
          fps_limit_method = "late";
          # Load MangoHud for every Steam game, but keep it hidden until
          # the toggle key is pressed.
          no_display = true;
          toggle_hud = "Alt_L+G";
          fps = true;
          frametime = true;
          frame_timing = true;
          cpu_stats = true;
          cpu_temp = true;
          gpu_stats = true;
          gpu_temp = true;
          gpu_power = true;
          throttling_status = true;
          ram = true;
          vram = true;
        };
      };
      # Use with single-player Steam games via launch options:
      # MANGOHUD_CONFIGFILE=/home/surya/.config/MangoHud/singleplayer.conf %command%
      home.file.".config/MangoHud/singleplayer.conf".text = ''
        fps_limit=170
        fps_limit_method=early
        no_display
        toggle_hud=Alt_L+G
        fps
        frametime
        frame_timing
        cpu_stats
        cpu_temp
        gpu_stats
        gpu_temp
        gpu_power
        throttling_status
        ram
        vram
      '';
      # Onimusha: Way of the Sword (Steam app 2638890). Select explicitly
      # with MANGOHUD_CONFIGFILE so the shared single-player cap stays unchanged.
      home.file.".config/MangoHud/onimusha-wots.conf".text = ''
        fps_limit=150
        fps_limit_method=early
        no_display
        toggle_hud=Alt_L+G
        fps
        frametime
        frame_timing
        cpu_stats
        cpu_temp
        gpu_stats
        gpu_temp
        gpu_power
        throttling_status
        ram
        vram
      '';
    };
  };
}
