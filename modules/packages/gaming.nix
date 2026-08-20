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
        openrgb
        mangojuice
      ];

      programs = {
        gamemode.enable = true;
        steam = {
          enable = true;
          gamescopeSession.enable = true;
          package = pkgs.steam.override {
            extraPkgs = (
              pkgs: with pkgs; [
                gamemode
              ]
            );
          };
        };
      };

      systemd.tmpfiles.rules = [
        "C+ /home/surya/.local/share/Steam/steam_dev.cfg 0644 surya users - ${steamDevCfg}"
      ];
    };
  };
}
