{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    discord
    geekbench
    bottles
    gamescope
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
