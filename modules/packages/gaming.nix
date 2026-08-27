# Gaming packages (NixOS)
{ lib, ... }:
{
  options.flake.modules.nixos.gaming = lib.mkOption {
    type = lib.types.deferredModule;
    default = { pkgs, ... }:
    let
      # HTTP/2 on the 32-bit Linux client is the usual Windows-vs-Linux
      # gap. Do not add @cMaxInitialDownloadSources — extra sockets stall
      # Steam's writer on large .ucas/.vpk files (write gaps), with or
      # without btrfs CoW.
      steamDevCfg = pkgs.writeText "steam_dev.cfg" ''
        @nClientDownloadEnableHTTP2PlatformLinux 0
      '';
    in
    {
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
          };
        };
        steam = {
          enable = true;
          gamescopeSession.enable = true;
          package = pkgs.steam.override {
            extraPkgs = (
              pkgs: with pkgs; [
                gamemode
                mangohud
              ]
            );
            extraProfile = ''
              export MANGOHUD=1
            '';
          };
        };
      };

      # Must run as the user. A system C+ rule creates
      # ~/.local/share/Steam as root and bootstraplinux_*.tar.xz cannot
      # extract (Cannot mkdir).
      systemd.user.tmpfiles.rules = [
        "C+ %h/.local/share/Steam/steam_dev.cfg 0644 - - - ${steamDevCfg}"
      ];
    };
  };

  options.flake.modules.homeManager.gaming = lib.mkOption {
    type = lib.types.deferredModule;
    default = { ... }: {
      programs.mangohud = {
        enable = true;
        settings = {
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
    };
  };
}
