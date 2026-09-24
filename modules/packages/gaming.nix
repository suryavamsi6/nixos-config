# Gaming packages (NixOS)
{ lib, ... }:
{
  options.flake.modules.nixos.gaming = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { pkgs, ... }:
      {
        # HTTP/2 is disabled in the Steam client through the user config below.
        environment.systemPackages = with pkgs; [
          gamescope
          protonup-ng
          mangohud
          trigger-control
          wine
          heroic
          bottles
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
            gamescopeSession.enable = true;
            extraCompatPackages = [
              pkgs.proton-cachyos
              pkgs.proton-ge-bin
            ];
            package = pkgs.steam.override {
              extraPkgs = (
                pkgs: with pkgs; [
                  gamemode
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
