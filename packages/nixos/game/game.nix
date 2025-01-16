{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    discord
  ];
  programs.steam.enable = true;
}
