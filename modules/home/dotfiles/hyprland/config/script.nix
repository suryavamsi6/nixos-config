{ pkgs, ... }:
{
  home.file.".config/hypr/toggle-laptop.sh" = {
    text = ''
      #!/bin/bash

      # Get current status of eDP-1
      STATUS=$(hyprctl monitors | grep -w "eDP-1")

      if [[ -z "$STATUS" ]]; then
        # If eDP-1 is disabled, enable it
        hyprctl keyword monitor "eDP-1,2560x1440@165,0x0,1"
      else
        # If eDP-1 is enabled, disable it
        hyprctl keyword monitor "eDP-1,disable"
      fi
    '';
  };

  home.file.".config/hypr/toggle-monitor.sh" = {
    text = ''
      #!/bin/bash

      # Get current status of DP-1
      STATUS=$(hyprctl monitors | grep -w "DP-1")

      if [[ -z "$STATUS" ]]; then
        # If DP-1 is disabled, enable it
        hyprctl keyword monitor "DP-1,2560x1440@144,2560x0,1"
      else
        # If DP-1 is enabled, disable it
        hyprctl keyword monitor "DP-1,disable"
      fi
    '';
  };
}
