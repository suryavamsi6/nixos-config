{ pkgs, ... }:
{
  exec-once = [
    "echo \"Xft.dpi: 96\" | xrdb -merge"
    "xprop -root -f _XWAYLAND_GLOBAL_OUTPUT_SCALE 32c -set _XWAYLAND_GLOBAL_OUTPUT_SCALE 1"
    "walker --gapplication-service"
    "hyprpanel"
    "kanshi"
  ];
}
