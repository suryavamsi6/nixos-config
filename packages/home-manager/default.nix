{ pkgs, inputs, ... }:
{

  imports = [
    ./dev/dev.nix
    ./work/work.nix
    ./game/game.nix
  ];

  home.packages = with pkgs; [
    inputs.zen-browser.packages."${system}".default
  ];
}
