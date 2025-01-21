{
  config,
  pkgs,
  ...
}:

{

  imports = [
    ./../../../modules/home/default.nix
    ./../../../packages/home/default.nix
  ];

  home.username = "surya";
  home.homeDirectory = "/home/surya";

  home.stateVersion = "24.11";

  hyprland-config1.enable = true;

  programs.home-manager.enable = true;

  home.pointerCursor = {
    gtk.enable = true;
    # x11.enable = true;
    package = pkgs.bibata-cursors;
    name = "Bibata-Modern-Classic";
    size = 16;
  };

  gtk = {
    enable = true;

    theme = {
      package = pkgs.flat-remix-gtk;
      name = "Flat-Remix-GTK-Grey-Darkest";
    };

    iconTheme = {
      package = pkgs.adwaita-icon-theme;
      name = "Adwaita";
    };

    font = {
      name = "Sans";
      size = 11;
    };
  };

}
