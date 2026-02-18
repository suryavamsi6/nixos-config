# macOS system preferences via nix-darwin
{ ... }:
{
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
      TrackpadThreeFingerDrag = true; # Three-finger drag, workspaces move to four-finger swipe
    };

    # Login window
    loginwindow = {
      GuestEnabled = false;
    };

    # Three-finger drag via Accessibility (required on modern macOS)
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
}
