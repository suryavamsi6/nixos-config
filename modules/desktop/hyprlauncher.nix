# Hyprlauncher — Spotlight-like Hyprland launcher (home-manager)
{ lib, ... }:
{
  options.flake.modules.homeManager.hyprlauncher = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { pkgs, ... }:
      {
        # Colorful icons so hyprlauncher can resolve desktop entry icons
        home.packages = [ pkgs.papirus-icon-theme ];

        # Shared look for all hyprtoolkit apps (hyprlauncher theming lives here)
        xdg.configFile."hypr/hyprtoolkit.conf".text = ''
          # Spotlight-inspired dark glass panel
          background = rgba(18, 18, 20, 0.92)
          base = rgba(32, 32, 36, 0.95)
          alternate_base = rgba(48, 48, 54, 0.90)
          text = rgba(245, 245, 247, 1.0)
          bright_text = rgba(255, 255, 255, 1.0)
          accent = rgba(10, 132, 255, 1.0)
          accent_secondary = rgba(94, 92, 230, 1.0)

          h1_size = 22
          h2_size = 17
          h3_size = 14
          font_size = 14
          small_font_size = 12

          icon_theme = Papirus-Dark
          font_family = Inter
          font_family_monospace = JetBrainsMono Nerd Font

          rounding_large = 22
          rounding_small = 12
        '';

        xdg.configFile."hypr/hyprlauncher.conf".text = ''
          general {
              grab_focus = true
          }

          cache {
              enabled = true
          }

          finders {
              default_finder = desktop
              math_prefix = =
              unicode_prefix = .
              font_prefix = '
              desktop_icons = true
          }

          ui {
              # Wide centered panel, closer to Spotlight proportions
              window_size = 720, 480
          }
        '';
      };
  };
}
