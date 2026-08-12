# GTK/Qt theme + cursor (home-manager) — dark preference
{ lib, ... }:
{
  options.flake.modules.homeManager.gtkTheme = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { config, pkgs, ... }:
      {
        home.pointerCursor = {
          enable = true;
          gtk.enable = true;
          package = pkgs.bibata-cursors;
          name = "Bibata-Modern-Classic";
          size = 16;
        };

        # Portal / libadwaita / GNOME apps honor this over gtk-theme-name alone
        dconf.settings."org/gnome/desktop/interface" = {
          color-scheme = "prefer-dark";
          gtk-theme = "Orchis-Dark";
          icon-theme = "Adwaita";
        };

        gtk = {
          enable = true;

          theme = {
            package = pkgs.orchis-theme;
            name = "Orchis-Dark";
          };

          # Keep gtk4 theme in sync (new HM default is null since 26.05)
          gtk4.theme = config.gtk.theme;

          iconTheme = {
            package = pkgs.adwaita-icon-theme;
            name = "Adwaita";
          };

          font = {
            name = "Sans";
            size = 11;
          };

          gtk3.extraConfig = {
            gtk-application-prefer-dark-theme = 1;
          };

          gtk4.extraConfig = {
            gtk-application-prefer-dark-theme = 1;
          };
        };

        qt = {
          enable = true;
          platformTheme.name = "gtk3";
          style.name = "adwaita-dark";
        };

        home.sessionVariables = {
          GTK_THEME = "Orchis-Dark";
        };
      };
  };
}
