hl.on("hyprland.start", function()
  local home = os.getenv("HOME") or "/home/surya"
  local scripts = home .. "/.config/hypr/scripts"
  local shell = scripts .. "/quickshell/Shell.qml"

  hl.exec_cmd('echo "Xft.dpi: 96" | xrdb -merge')
  hl.exec_cmd("xprop -root -f _XWAYLAND_GLOBAL_OUTPUT_SCALE 32c -set _XWAYLAND_GLOBAL_OUTPUT_SCALE 1")
  -- hyprpolkitagent / hypridle / swayosd / quickshell are started by systemd user units
  hl.exec_cmd("sh -c 'pgrep -x awww-daemon >/dev/null || exec awww-daemon'")
  -- systemd starts Serpantinum; only spawn it if that unit is not already up
  hl.exec_cmd("sh -c 'pgrep -f \"quickshell.*Shell.qml\" >/dev/null || exec qs -p " .. shell .. "'")
  hl.exec_cmd("sh -c 'pgrep -x playerctld >/dev/null || exec playerctld'")
  hl.exec_cmd("sh -c 'pgrep -x blueman-applet >/dev/null || exec blueman-applet'")
  hl.exec_cmd("wl-paste --type text --watch cliphist store")
  hl.exec_cmd("wl-paste --type image --watch cliphist store")
  hl.exec_cmd("sh -c 'pgrep -f volume_listener.sh >/dev/null || exec bash " .. scripts .. "/volume_listener.sh'")
  hl.exec_cmd("sh -c 'pgrep -f focus_daemon.py >/dev/null || exec python3 " .. scripts .. "/quickshell/focustime/focus_daemon.py'")
end)
