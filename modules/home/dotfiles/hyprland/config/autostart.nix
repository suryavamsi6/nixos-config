{ ... }:
{
  exec-once = [
    "echo \"Xft.dpi: 96\" | xrdb -merge"
    "xprop -root -f _XWAYLAND_GLOBAL_OUTPUT_SCALE 32c -set _XWAYLAND_GLOBAL_OUTPUT_SCALE 1"
    "swaync -c /home/surya/.config/swaync/config.json -s /home/surya/.config/swaync/style.css"
    "walker --gapplication-service"
    "systemctl --user start hyprpolkitagent"
    "ags run .config/ags/yami.js"
    "hypridle"
    "hyprpaper"
  ];
}
