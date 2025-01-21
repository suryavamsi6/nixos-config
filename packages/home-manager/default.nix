{ pkgs, inputs, ... }:
{

  imports = [
    ./dev/dev.nix
    ./work/work.nix
    ./bar/ags.nix
  ];

  home.packages = with pkgs; [
    inputs.zen-browser.packages."${system}".default
    inputs.ags.packages."${system}".default
  ];
}
