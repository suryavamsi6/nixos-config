{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    gamescope
    protonup
    mangohud
    trigger-control
    wine
    heroic
    bottles
    qbittorrent
    openrgb
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
}
