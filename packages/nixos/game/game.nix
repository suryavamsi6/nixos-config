{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    discord
    geekbench
    bottles
  ];
  programs.steam.enable = true;
}
