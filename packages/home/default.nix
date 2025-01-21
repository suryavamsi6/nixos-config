{ pkgs, inputs, ... }:
{

  imports = [
    ./dev/dev.nix
    ./work/work.nix
    ./ags/ags.nix
  ];

  home.packages = with pkgs; [
    inputs.zen-browser.packages."${system}".default
  ];
}
