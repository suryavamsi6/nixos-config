# macOS system defaults (Darwin)
{ lib, ... }:
{
  options.flake.modules.darwin.defaults = lib.mkOption {
    type = lib.types.deferredModule;
    default = { ... }: {
      system.defaults = {
        # Dock
        dock = {
          autohide = false;
          show-recents = true;
          tilesize = 48;
          magnification = false;
          orientation = "bottom";
          minimize-to-application = false;
          mru-spaces = true;
        };

        # Finder
        finder = {
          AppleShowAllExtensions = true;
          FXPreferredViewStyle = "Nlsv"; # List view
          ShowPathbar = true;
          ShowStatusBar = true;
          _FXShowPosixPathInTitle = true;
        };

        # Global preferences
        NSGlobalDomain = {
          AppleInterfaceStyle = "Dark";
          AppleShowAllExtensions = true;
          InitialKeyRepeat = 15;
          KeyRepeat = 2;
          NSAutomaticCapitalizationEnabled = false;
          NSAutomaticSpellingCorrectionEnabled = false;
          "com.apple.swipescrolldirection" = true; # Natural scrolling
        };

        # Trackpad
        trackpad = {
          Clicking = true; # Tap to click
          TrackpadRightClick = true; # Two-finger right click
          TrackpadThreeFingerDrag = true; # Three-finger drag
        };

        # Login window
        loginwindow = {
          GuestEnabled = false;
        };

        # Three-finger drag via Accessibility
        CustomUserPreferences = {
          "com.apple.AppleMultitouchTrackpad" = {
            TrackpadThreeFingerDrag = true;
            Dragging = true;
          };
          "com.apple.driver.AppleBluetoothMultitouch.trackpad" = {
            TrackpadThreeFingerDrag = true;
            Dragging = true;
          };
        };
      };
    };
  };
}
