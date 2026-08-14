# Serpantinum Quickshell desktop (bar, launcher, lock, matugen, awww, swayosd)
{ lib, ... }:
{
  options.flake.modules.homeManager.serpantinum = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { inputs, pkgs, config, lib, ... }:
      let
        dots = inputs.serpantinum;

        qsPkg = inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default;
        qtQml = pkg: "${pkg}/lib/qt-6/qml";
        qmlPaths = lib.concatStringsSep ":" [
          (qtQml pkgs.kdePackages.qt5compat)
          (qtQml pkgs.kdePackages.qtmultimedia)
          (qtQml pkgs.kdePackages.qtwebsockets)
          (qtQml pkgs.kdePackages.qtwebengine)
        ];
        qsWrapped = pkgs.runCommand "quickshell-serpantinum" {
          nativeBuildInputs = [ pkgs.makeWrapper ];
          meta.mainProgram = "qs";
        } ''
          mkdir -p $out/bin
          for bin in qs quickshell; do
            if [ -e "${qsPkg}/bin/$bin" ]; then
              makeWrapper "${qsPkg}/bin/$bin" "$out/bin/$bin" \
                --prefix NIXPKGS_QT6_QML_IMPORT_PATH : "${qmlPaths}" \
                --prefix QML2_IMPORT_PATH : "${qmlPaths}"
            fi
          done
        '';

        matugenReload = pkgs.writeShellScript "matugen_reload.sh" ''
          set -euo pipefail

          killall -USR1 kitty 2>/dev/null || true
          killall -USR1 .kitty-wrapped 2>/dev/null || true

          apply_hypr_borders() {
            local colors_lua="''${HOME}/.config/hypr/colors.lua"
            [ -f "$colors_lua" ] || return 0
            local active inactive
            active=$(sed -n 's/.*active_border = "\(rgba([^"]*)\)".*/\1/p' "$colors_lua" | head -n1)
            inactive=$(sed -n 's/.*inactive_border = "\(rgba([^"]*)\)".*/\1/p' "$colors_lua" | head -n1)
            [ -n "$active" ] && [ -n "$inactive" ] || return 0
            hyprctl eval "hl.config({ general = { col = { active_border = { colors = { \"$active\" }, angle = 45 }, inactive_border = \"$inactive\" } } })" >/dev/null 2>&1 || true
          }
          apply_hypr_borders

          if pgrep -x "cava" > /dev/null; then
            cat ~/.config/cava/config_base ~/.config/cava/colors > ~/.config/cava/config 2>/dev/null || true
            killall -USR1 cava 2>/dev/null || true
          fi

          if command -v swaync-client &> /dev/null; then
            swaync-client -rs || true
          fi

          if systemctl --user is-active --quiet swayosd.service; then
            systemctl --user restart swayosd.service &
          fi

          if command -v gsettings &> /dev/null; then
            gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita' || true
            sleep 0.05
            gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark' || true
            gsettings set org.gnome.desktop.interface color-scheme 'default' || true
            sleep 0.05
            gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' || true
          fi

          wait
        '';

        patchTopBar = pkgs.writeText "patch-serpantinum-topbar.py" ''
          from pathlib import Path
          import sys

          p = Path(sys.argv[1])
          t = p.read_text()

          replacements = [
              (
                  'opacity: barWindow.showEthernet ? (barWindow.ethStatus === "Connected" ? 1.0 : 0.0) : (barWindow.isWifiOn ? 1.0 : 0.0)',
                  'opacity: barWindow.isWifiOn ? 1.0 : 0.0',
              ),
              (
                  'text: barWindow.showEthernet ? "󰈀" : barWindow.wifiIcon;',
                  'text: barWindow.wifiIcon;',
              ),
              (
                  'color: barWindow.showEthernet ? (barWindow.ethStatus === "Connected" ? mocha.base : mocha.subtext0) : (barWindow.isWifiOn ? mocha.base : mocha.subtext0)',
                  'color: barWindow.isWifiOn ? mocha.base : mocha.subtext0',
              ),
              (
                  'text: barWindow.showEthernet ? barWindow.ethStatus : ((barWindow.isWifiOn ? (barWindow.wifiSsid !== "" ? barWindow.wifiSsid : "On") : "Off"))',
                  'text: barWindow.isWifiOn ? ((barWindow.wifiSsid !== "" && barWindow.wifiSsid !== "Ethernet") ? barWindow.wifiSsid : "On") : "Off"',
              ),
              (
                  'color: barWindow.showEthernet ? (barWindow.ethStatus === "Connected" ? mocha.base : mocha.text) : (barWindow.isWifiOn ? mocha.base : mocha.text);',
                  'color: barWindow.isWifiOn ? mocha.base : mocha.text;',
              ),
              (
                  'property real targetWidth: barWindow.isDesktop ? 0 : btLayoutRow.implicitWidth + barWindow.s(24)',
                  'property real targetWidth: btLayoutRow.implicitWidth + barWindow.s(24)',
              ),
          ]
          for old, new in replacements:
              if old not in t:
                  raise SystemExit(f"TopBar patch missing string:\n{old}")
              t = t.replace(old, new, 1)

          import re
          bt_pat = r'text: barWindow\.btDevice\n\s+visible: text !== "";[ ]*'
          bt_new = 'text: !barWindow.isBtOn ? "Off" : ((barWindow.btDevice !== "" && barWindow.btDevice !== "Disconnected" && barWindow.btDevice !== "Off") ? barWindow.btDevice : "On")\n                                        visible: true;'
          t, n = re.subn(bt_pat, bt_new, t, count=1)
          if n != 1:
              raise SystemExit("TopBar patch missing bluetooth label")

          eth = """                            Rectangle {
                                id: ethPill
                                property bool isHovered: ethMouse.containsMouse
                                radius: barWindow.s(10); height: sysLayout.pillHeight;
                                color: isHovered ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.6) : Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, 0.4)
                                clip: true
                                Rectangle {
                                    anchors.fill: parent
                                    radius: barWindow.s(10)
                                    opacity: barWindow.ethStatus === "Connected" ? 1.0 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: 300 } }
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: mocha.blue }
                                        GradientStop { position: 1.0; color: Qt.lighter(mocha.blue, 1.3) }
                                    }
                                }
                                property real targetWidth: ethLayoutRow.implicitWidth + barWindow.s(24)
                                width: targetWidth
                                Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutQuint } }
                                scale: isHovered ? 1.05 : 1.0
                                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                                Behavior on color { ColorAnimation { duration: 200 } }
                                property bool initAnimTrigger: false
                                Timer { running: rightContent.showLayout && !parent.initAnimTrigger; interval: 40; onTriggered: parent.initAnimTrigger = true }
                                opacity: initAnimTrigger ? 1 : 0
                                transform: Translate { y: parent.initAnimTrigger ? 0 : barWindow.s(15); Behavior on y { NumberAnimation { duration: 500; easing.type: Easing.OutBack } } }
                                Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                                Row {
                                    id: ethLayoutRow
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: barWindow.s(12)
                                    spacing: barWindow.s(8)
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "󰈀"
                                        font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(16)
                                        color: barWindow.ethStatus === "Connected" ? mocha.base : mocha.subtext0
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: barWindow.ethStatus === "Connected" ? "Eth" : "Off"
                                        font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(13); font.weight: Font.Black
                                        color: barWindow.ethStatus === "Connected" ? mocha.base : mocha.text
                                    }
                                }
                                MouseArea { id: ethMouse; hoverEnabled: true; anchors.fill: parent; onClicked: Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/qs_manager.sh toggle network eth"]) }
                            }

          """
          marker = "                            Rectangle {\n                                id: wifiPill"
          if marker not in t:
              raise SystemExit("TopBar patch missing wifiPill marker")
          t = t.replace(marker, eth + marker, 1)
          p.write_text(t)
        '';

        patchBtPanel = pkgs.writeText "patch-serpantinum-bt-panel.py" ''
          from pathlib import Path
          import sys
          import textwrap

          p = Path(sys.argv[1])
          t = p.read_text()
          start = t.index("get_status() {")
          end = t.index("\ntoggle_power() {")
          repl = textwrap.dedent(
              """
              get_status() {
                  source "$(dirname "''${BASH_SOURCE[0]}")/../watchers/bt_dbus.sh"
                  if ! declare -F bt_dbus_panel_status >/dev/null; then
                      echo '{"present":true,"power":"off","connected":[],"devices":[]}'
                      return
                  fi
                  bt_dbus_panel_status
              }

              """
          ).lstrip("\n")
          p.write_text(t[:start] + repl + t[end + 1 :])
        '';

        # Upstream only scans /usr and ~/.nix-profile. Home Manager with
        # useUserPackages puts .desktop files in /etc/profiles/per-user/$USER.
        appFetcher = pkgs.writeText "app_fetcher.py" ''
          #!/usr/bin/env python3
          import glob
          import json
          import os

          def add_dir(dirs, seen, path):
              if not path:
                  return
              key = os.path.normpath(path)
              if key in seen:
                  return
              seen.add(key)
              dirs.append(path)

          def desktop_dirs():
              dirs = []
              seen = set()
              home = os.path.expanduser("~")
              user = os.environ.get("USER") or os.path.basename(home)

              data_home = os.environ.get("XDG_DATA_HOME") or os.path.join(home, ".local/share")
              add_dir(dirs, seen, os.path.join(data_home, "applications"))

              data_dirs = os.environ.get("XDG_DATA_DIRS", "")
              if data_dirs:
                  for part in data_dirs.split(":"):
                      if part:
                          add_dir(dirs, seen, os.path.join(part, "applications"))

              for extra in (
                  os.path.join(home, ".nix-profile/share/applications"),
                  "/etc/profiles/per-user/" + user + "/share/applications",
                  "/run/current-system/sw/share/applications",
                  "/var/lib/flatpak/exports/share/applications",
                  os.path.join(home, ".local/share/flatpak/exports/share/applications"),
                  "/var/lib/snapd/desktop/applications",
              ):
                  add_dir(dirs, seen, extra)
              return dirs

          def parse_desktop(path):
              app = {"name": "", "exec": "", "icon": ""}
              in_entry = False
              no_display = False
              hidden = False
              entry_type = "Application"

              with open(path, "r", encoding="utf-8", errors="replace") as fh:
                  for raw in fh:
                      line = raw.strip()
                      if line == "[Desktop Entry]":
                          in_entry = True
                          continue
                      if line.startswith("[") and line.endswith("]"):
                          in_entry = False
                          continue
                      if not in_entry or "=" not in line:
                          continue
                      key, value = line.split("=", 1)
                      if key == "Name" and not app["name"]:
                          app["name"] = value
                      elif key == "Exec" and not app["exec"]:
                          app["exec"] = value.split(" %")[0].split(" @@")[0].strip()
                      elif key == "Icon" and not app["icon"]:
                          app["icon"] = value
                      elif key == "Type":
                          entry_type = value
                      elif key == "NoDisplay" and value.lower() in ("true", "1"):
                          no_display = True
                      elif key == "Hidden" and value.lower() in ("true", "1"):
                          hidden = True

              if no_display or hidden or entry_type != "Application":
                  return None
              if not app["name"] or not app["exec"]:
                  return None
              return app

          def fetch_apps():
              apps = {}
              for d in desktop_dirs():
                  if not os.path.isdir(d):
                      continue
                  for f in glob.glob(os.path.join(d, "**/*.desktop"), recursive=True):
                      desktop_id = os.path.basename(f)
                      if desktop_id in apps:
                          continue
                      try:
                          app = parse_desktop(f)
                      except OSError:
                          continue
                      if app:
                          apps[desktop_id] = app

              res = list(apps.values())
              res.sort(key=lambda x: x["name"].lower())
              print(json.dumps(res))

          if __name__ == "__main__":
              fetch_apps()
        '';

        # bluetoothctl registers an AdvertisementMonitor on every invocation.
        # The bar/network popup were spawning it every few seconds, which
        # drops A2DP on the MediaTek mt7921 adapter. Query BlueZ over D-Bus.
        btDbus = pkgs.writeText "bt_dbus.sh" ''
          bt_dbus_adapter() {
            ${pkgs.systemd}/bin/busctl --system tree org.bluez --list 2>/dev/null \
              | grep -E '^/org/bluez/hci[0-9]+$' | head -n1
          }
          bt_dbus_prop() {
            ${pkgs.systemd}/bin/busctl --system get-property org.bluez "$1" "$2" "$3" 2>/dev/null
          }
          bt_dbus_bool() { bt_dbus_prop "$@" | grep -q 'true'; }
          bt_dbus_str() { bt_dbus_prop "$@" | sed -n 's/^s "\(.*\)"$/\1/p'; }
          bt_dbus_byte() { bt_dbus_prop "$@" | awk '/^y / {print $2}'; }
          bt_dbus_devices() {
            local ad
            ad=$(bt_dbus_adapter)
            [ -n "$ad" ] || return 0
            ${pkgs.systemd}/bin/busctl --system tree org.bluez --list 2>/dev/null | grep -E "^''${ad}/dev_[^/]+$"
          }
          bt_dbus_jq_escape() { ${pkgs.jq}/bin/jq -n --arg s "$1" '$s'; }

          bt_dbus_panel_status() {
            local ad power connected_json devices_json c_objs d_objs
            ad=$(bt_dbus_adapter)
            if [ -z "$ad" ]; then
              echo '{"present":false,"power":"off","connected":[],"devices":[]}'
              return
            fi
            power="off"
            bt_dbus_bool "$ad" org.bluez.Adapter1 Powered && power="on"
            connected_json="[]"
            devices_json="[]"
            c_objs=()
            d_objs=()
            if [ "$power" = on ]; then
              local dev addr alias icon icon_type bat name_esc icon_esc
              for dev in $(bt_dbus_devices); do
                addr=$(bt_dbus_str "$dev" org.bluez.Device1 Address)
                [ -n "$addr" ] || continue
                alias=$(bt_dbus_str "$dev" org.bluez.Device1 Alias)
                [ -z "$alias" ] && alias="$addr"
                icon_type=$(bt_dbus_str "$dev" org.bluez.Device1 Icon)
                icon=""
                case "''${icon_type,,} ''${alias,,}" in
                  *headset*|*headphone*|*buds*|*pods*) icon="🎧" ;;
                  *audio*|*speaker*) icon="🔊" ;;
                  *keyboard*) icon="" ;;
                  *mouse*) icon="" ;;
                  *phone*) icon="" ;;
                esac
                name_esc=$(bt_dbus_jq_escape "$alias")
                icon_esc=$(bt_dbus_jq_escape "$icon")
                if bt_dbus_bool "$dev" org.bluez.Device1 Connected; then
                  bat=$(bt_dbus_byte "$dev" org.bluez.Battery1 Percentage)
                  [ -z "$bat" ] && bat="0"
                  c_objs+=("{\"id\":$(bt_dbus_jq_escape "$addr"),\"name\":$name_esc,\"mac\":$(bt_dbus_jq_escape "$addr"),\"icon\":$icon_esc,\"battery\":\"$bat\",\"profile\":\"Connected\"}")
                elif bt_dbus_bool "$dev" org.bluez.Device1 Paired; then
                  d_objs+=("{\"id\":$(bt_dbus_jq_escape "$addr"),\"name\":$name_esc,\"mac\":$(bt_dbus_jq_escape "$addr"),\"icon\":$icon_esc,\"action\":\"Connect\"}")
                fi
              done
              if [ ''${#c_objs[@]} -gt 0 ]; then
                connected_json="[$(IFS=,; echo "''${c_objs[*]}")]"
              fi
              if [ ''${#d_objs[@]} -gt 0 ]; then
                devices_json="[$(IFS=,; echo "''${d_objs[*]}")]"
              fi
            fi
            echo "{\"present\":true,\"power\":\"$power\",\"connected\":$connected_json,\"devices\":$devices_json}"
          }
        '';
        btFetch = pkgs.writeText "bt_fetch.sh" ''
          #!/usr/bin/env bash
          source "$(dirname "''${BASH_SOURCE[0]}")/bt_dbus.sh"
          ad=$(bt_dbus_adapter)
          if [ -z "$ad" ] || ! bt_dbus_bool "$ad" org.bluez.Adapter1 Powered; then
            ${pkgs.jq}/bin/jq -n -c '{status:"off",icon:"󰂲",connected:"Off"}'
            exit 0
          fi
          name=""
          any=0
          for dev in $(bt_dbus_devices); do
            bt_dbus_bool "$dev" org.bluez.Device1 Connected || continue
            any=1
            icon=$(bt_dbus_str "$dev" org.bluez.Device1 Icon)
            alias=$(bt_dbus_str "$dev" org.bluez.Device1 Alias)
            case "$icon" in
              audio-headset|audio-headphones|audio-card) name=$alias; break ;;
            esac
            [ -z "$name" ] && name=$alias
          done
          if [ "$any" -eq 1 ]; then
            ${pkgs.jq}/bin/jq -n -c --arg n "''${name:-Connected}" '{status:"on",icon:"󰂱",connected:$n}'
          else
            ${pkgs.jq}/bin/jq -n -c '{status:"on",icon:"󰂯",connected:"Disconnected"}'
          fi
        '';

        hyprScripts = pkgs.runCommand "serpantinum-hypr-scripts" { } ''
          mkdir -p $out
          cp -a ${dots}/config/sessions/hyprland/scripts/. $out/
          chmod -R u+w $out
          cp ${appFetcher} $out/quickshell/applauncher/app_fetcher.py
          cp ${btDbus} $out/quickshell/watchers/bt_dbus.sh
          cp ${btFetch} $out/quickshell/watchers/bt_fetch.sh
          chmod +x $out/quickshell/watchers/bt_dbus.sh $out/quickshell/watchers/bt_fetch.sh

          find $out -type f \( -name '*.sh' -o -name '*.py' -o -name '*.qml' -o -name '*.js' \) -print0 \
            | xargs -0 sed -i \
              -e 's|/home/ilyamiro|/home/surya|g' \
              -e 's|/usr/bin/firefox|zen-twilight|g' \
              -e 's/swww-daemon/awww-daemon/g' \
              -e 's/\bswww\b/awww/g'

          # Hyprland Lua no longer accepts hyprlang `dispatch workspace N`.
          substituteInPlace $out/qs_manager.sh \
            --replace-fail 'hyprctl --batch "dispatch $CMD" >/dev/null 2>&1' \
            'if [[ "$TARGET" == "move" ]]; then hyprctl dispatch "hl.dsp.window.move({ workspace = $ACTION })" >/dev/null 2>&1; else hyprctl dispatch "hl.dsp.focus({ workspace = $ACTION })" >/dev/null 2>&1; fi'

          substituteInPlace $out/quickshell/Main.qml \
            --replace-fail 'focusable: true' 'focusable: isVisible'

          substituteInPlace $out/quickshell/applauncher/appLauncher.qml \
            --replace-fail 'Quickshell.execDetached(["hyprctl", "dispatch", "exec", "--", execStr]);' \
                           'Quickshell.execDetached(["bash", "-c", execStr]);'

          substituteInPlace $out/quickshell/settings/SettingsPopup.qml \
            --replace-fail '["hyprctl", "dispatch", "submap", "reset"]' \
                           '["hyprctl", "dispatch", "hl.dsp.submap(\"reset\")"]' \
            --replace-fail '["hyprctl", "dispatch", "submap", "passthru"]' \
                           '["hyprctl", "dispatch", "hl.dsp.submap(\"passthru\")"]'

          if [ -f $out/exit.sh ]; then
            substituteInPlace $out/exit.sh \
              --replace-fail 'hyprctl dispatch exit' 'hyprctl dispatch "hl.dsp.exit()"'
          fi

          # Non-interactive matugen (Quickshell, systemd) cannot prompt for a source color.
          find $out -type f \( -name '*.sh' -o -name '*.qml' -o -name '*.js' \) -print0 \
            | xargs -0 sed -i 's/matugen image/matugen --prefer darkness image/g'

          substituteInPlace $out/quickshell/Config.qml \
            --replace-fail 'readonly property string weatherEnvPath: qsScriptsDir + "/calendar/.env"' \
                           'readonly property string weatherEnvPath: hyprDir + "/openweather.env"'

          substituteInPlace $out/quickshell/calendar/weather.sh \
            --replace-fail 'ENV_FILE="$(dirname "$0")/.env"' \
                           'ENV_FILE="''${XDG_CONFIG_HOME:-$HOME/.config}/hypr/openweather.env"
if [ ! -f "$ENV_FILE" ]; then
    ENV_FILE="$(dirname "$0")/.env"
fi'

          # Avoid embedding quote-hash patterns that terminate Nix indented strings.
          sed -i \
            -e 's!if \[ -f "$ENV_FILE" \]; then!if [ -f "$ENV_FILE" ] \&\& grep -qE "^[[:space:]]*OPENWEATHER_" "$ENV_FILE"; then!' \
            -e 's!export $(grep -v .^#. "$ENV_FILE" | xargs)!set -a; source "$ENV_FILE" >/dev/null; set +a!' \
            $out/quickshell/calendar/weather.sh

          substituteInPlace $out/quickshell/TopBar.qml \
            --replace-fail 'echo "$(~/.config/hypr/scripts/quickshell/calendar/weather.sh --current-icon)"
                    echo "$(~/.config/hypr/scripts/quickshell/calendar/weather.sh --current-temp)"
                    echo "$(~/.config/hypr/scripts/quickshell/calendar/weather.sh --current-hex)"' \
                           'icon=$(~/.config/hypr/scripts/quickshell/calendar/weather.sh --current-icon 2>/dev/null | tail -n1)
                    temp=$(~/.config/hypr/scripts/quickshell/calendar/weather.sh --current-temp 2>/dev/null | tail -n1)
                    hex=$(~/.config/hypr/scripts/quickshell/calendar/weather.sh --current-hex 2>/dev/null | tail -n1)
                    printf "%s\n%s\n%s\n" "$icon" "$temp" "$hex"'

          substituteInPlace $out/quickshell/calendar/weather.sh \
            --replace-fail '        if grep -q '"'"'"desc": "No API Key"'"'"' "$json_file"; then
            # Key is pending/invalid. Check once an hour.
            if [ $diff -gt $PENDING_RETRY_LIMIT ]; then
                touch "$json_file" # Bump file timestamp slightly to avoid spamming processes
                get_data &
            fi' \
                           '        if grep -q '"'"'"desc": "No API Key"'"'"' "$json_file"; then
            # Key was saved after dummy cache; fetch now instead of waiting an hour.
            if [[ -n "$KEY" && "$KEY" != "Skipped" && "$KEY" != "OPENWEATHER_KEY" ]]; then
                get_data
            elif [ $diff -gt $PENDING_RETRY_LIMIT ]; then
                touch "$json_file"
                get_data &
            fi'

          substituteInPlace $out/quickshell/watchers/network_fetch.sh \
            --replace-fail '    # Scenario 1: Ethernet is actively providing internet
    if [ "$iface_type" = "ethernet" ]; then
        status="enabled"
        ssid="Ethernet"
        icon="󰈀"
        eth_status="Connected"
        
    # Scenario 2: Wi-Fi is actively providing internet
    elif [ "$iface_type" = "wifi" ]; then' \
                           '    if [ "$iface_type" = "ethernet" ]; then
        eth_status="Connected"
    fi

    # Wi-Fi is reported independently so the bar can show both pills.
    if [ "$iface_type" = "wifi" ]; then'

          substituteInPlace $out/quickshell/TopBar.qml \
            --replace-fail 'barWindow.timeStr = Qt.formatDateTime(d, "HH:mm:ss");' \
                           'barWindow.timeStr = Qt.formatDateTime(d, "HH:mm");'
          ${pkgs.python3}/bin/python3 ${patchTopBar} $out/quickshell/TopBar.qml
          ${pkgs.python3}/bin/python3 ${patchBtPanel} $out/quickshell/network/bluetooth_panel_logic.sh

          substituteInPlace $out/qs_manager.sh \
            --replace-fail '{ echo "scan on"; sleep infinity; } | stdbuf -oL bluetoothctl > "$BT_SCAN_LOG" 2>&1 &' \
                           ': # bluetoothctl scan on drops A2DP on MediaTek; paired devices still list over D-Bus'

          substituteInPlace $out/quickshell/settings/SettingsPopup.qml \
            --replace-fail 'Workspaces (SUPER + 1-9)' 'Workspaces (SUPER + 1-0, SHIFT moves)' \
            --replace-fail 'model: 9' 'model: 10' \
            --replace-fail 'property int wsNum: index + 1' 'property int wsNum: index === 9 ? 0 : index + 1'

          cp ${matugenReload} $out/quickshell/wallpaper/matugen_reload.sh

          # Upstream school-timetable scraper (uddataplus + a private Firefox profile).
          # Without that login it only renders "Error / Check Script" on the calendar.
          rm -rf $out/quickshell/calendar/schedule

          find $out -type f \( -name '*.sh' -o -name '*.py' \) -exec chmod +x {} +
        '';

        hyprlandLuaTemplate = ''
          return {
            active_border = "rgba({{colors.primary.default.hex_stripped}}ee)",
            inactive_border = "rgba({{colors.on_primary_fixed_variant.default.hex_stripped}}aa)",
          }
        '';

        matugenToml = ''
          [config]
          reload_apps = false
          prefer = "darkness"

          [templates.quickshell]
          input_path = "~/.config/matugen/templates/qs_colors.json.template"
          output_path = "/tmp/qs_colors.json"

          [templates.quickshell_cache]
          input_path = "~/.config/matugen/templates/qs_colors.json.template"
          output_path = "~/.cache/matugen/qs_colors.json"

          [templates.kitty]
          input_path = "~/.config/matugen/templates/kitty-colors.conf.template"
          output_path = "/tmp/kitty-matugen-colors.conf"

          [templates.kitty_cache]
          input_path = "~/.config/matugen/templates/kitty-colors.conf.template"
          output_path = "~/.cache/matugen/kitty-colors.conf"

          [templates.cava]
          input_path = "~/.config/matugen/templates/cava-colors.ini.template"
          output_path = "~/.config/cava/colors"

          [templates.swayosd]
          input_path = "~/.config/matugen/templates/swayosd.css.template"
          output_path = "~/.config/swayosd/style.css"

          [templates.gtk]
          input_path = "~/.config/matugen/templates/gtk.css.template"
          output_path = "~/.cache/matugen/colors-gtk.css"

          [templates.qt5ct]
          input_path = "~/.config/matugen/templates/qtct.conf.template"
          output_path = "~/.config/qt5ct/colors/matugen.conf"

          [templates.qt6ct]
          input_path = "~/.config/matugen/templates/qtct.conf.template"
          output_path = "~/.config/qt6ct/colors/matugen.conf"

          [templates.qt5_style]
          input_path = "~/.config/matugen/templates/qt-style.qss.template"
          output_path = "~/.config/qt5ct/qss/matugen-style.qss"

          [templates.qt6_style]
          input_path = "~/.config/matugen/templates/qt-style.qss.template"
          output_path = "~/.config/qt6ct/qss/matugen-style.qss"

          [templates.hyprland]
          input_path = "~/.config/matugen/templates/hyprland.conf.template"
          output_path = "~/.config/hypr/colors.conf"

          [templates.hyprland_lua]
          input_path = "~/.config/matugen/templates/hyprland.lua.template"
          output_path = "~/.config/hypr/colors.lua"
        '';

        matugenCfg = pkgs.runCommand "serpantinum-matugen" { } ''
          mkdir -p $out/templates
          cp -a ${dots}/config/programs/matugen/templates/. $out/templates/
          chmod -R u+w $out
          printf '%s\n' ${lib.escapeShellArg matugenToml} > $out/config.toml
          printf '%s\n' ${lib.escapeShellArg hyprlandLuaTemplate} > $out/templates/hyprland.lua.template
        '';

        arcMidnight = pkgs.runCommand "arc-midnight-cursors" { } ''
          mkdir -p $out/share/icons
          ln -s ${pkgs.fetchzip {
            url = "https://github.com/yeyushengfan258/ArcMidnight-Cursors/archive/refs/heads/main.zip";
            hash = "sha256-VgOpt0rukW0+rSkLFoF9O0xO/qgwieAchAev1vjaqPE=";
          }}/dist $out/share/icons/ArcMidnight-Cursors
        '';

        gtkCssImport = ''@import url("file://${config.home.homeDirectory}/.cache/matugen/colors-gtk.css");'';

        mkBind = mods: key: dispatcher: command: {
          type = "bind";
          inherit mods key dispatcher command;
        };

        keybindsForSettings =
          [
            (mkBind "SUPER" "SPACE" "exec" "toggle applauncher")
            (mkBind "SUPER" "R" "exec" "toggle settings")
            (mkBind "SUPER" "Q" "exec" "kitty")
            (mkBind "SUPER" "RETURN" "exec" "kitty")
            (mkBind "SUPER" "E" "exec" "thunar")
            (mkBind "SUPER" "B" "exec" "zen-twilight")
            (mkBind "SUPER" "P" "exec" "hyprpicker -a")
            (mkBind "SUPER" "X" "killactive" "close window")
            (mkBind "SUPER" "C" "killactive" "close window")
            (mkBind "SUPER" "F" "togglefloating" "")
            (mkBind "SUPER + ALT" "F" "exec" "float 900x600 centered")
            (mkBind "SUPER" "M" "fullscreen" "")
            (mkBind "SUPER" "DOWN" "layout" "togglesplit")
            (mkBind "SUPER" "UP" "layout" "togglesplit")
            (mkBind "SUPER" "G" "togglegroup" "")
            (mkBind "SUPER" "L" "exec" "float 1440x1080")
            (mkBind "SUPER + CTRL" "left" "changegroupactive" "prev")
            (mkBind "SUPER + CTRL" "right" "changegroupactive" "next")
            (mkBind "SUPER + ALT" "F4" "exit" "")
            (mkBind "ALT" "F4" "killactive" "close window")
            (mkBind "SUPER" "left" "movefocus" "l")
            (mkBind "SUPER" "right" "movefocus" "r")
            (mkBind "SUPER + SHIFT" "up" "movefocus" "u")
            (mkBind "SUPER + SHIFT" "down" "movefocus" "d")
            (mkBind "SUPER + SHIFT" "left" "swapwindow" "l")
            (mkBind "SUPER + SHIFT" "right" "swapwindow" "r")
            (mkBind "SUPER" "H" "togglespecialworkspace" "magic")
            (mkBind "SUPER + SHIFT" "H" "movetoworkspace" "special:magic")
          ]
          ++ lib.concatMap (
            i:
            let
              key = toString (lib.mod i 10);
            in
            [
              (mkBind "SUPER" key "workspace" (toString i))
              (mkBind "SUPER + SHIFT" key "movetoworkspace" (toString i))
            ]
          ) (lib.range 1 10)
          ++ [
            (mkBind "SUPER + SHIFT" "S" "exec" "hyprshot region snip")
            (mkBind "" "Print" "exec" "screenshot overlay")
            (mkBind "SUPER" "Print" "exec" "screenshot full")
            (mkBind "SUPER + SHIFT" "Print" "exec" "screenshot full + edit")
            (mkBind "SUPER" "O" "exec" "screenshot edit")
            (mkBind "SUPER + SHIFT" "L" "exec" "lock")
            (mkBind "SUPER" "D" "exec" "toggle clipboard")
            (mkBind "SUPER" "W" "exec" "toggle wallpaper")
            (mkBind "SUPER" "N" "exec" "toggle network")
            (mkBind "SUPER" "V" "exec" "toggle volume")
            (mkBind "SUPER" "S" "exec" "toggle calendar")
            (mkBind "SUPER + SHIFT" "T" "exec" "toggle focustime")
            (mkBind "SUPER" "F1" "exec" "toggle-laptop.sh")
            (mkBind "SUPER" "F2" "exec" "toggle-monitor.sh")
          ];

        seedSettings = builtins.toJSON {
          uiScale = 1.0;
          keybinds = keybindsForSettings;
        };
        keybindsJson = builtins.toJSON keybindsForSettings;

        seedMatugen = pkgs.writeShellScript "serpantinum-seed-matugen" ''
          set -euo pipefail
          if [ -f /tmp/qs_colors.json ] && [ -f /tmp/kitty-matugen-colors.conf ]; then
            exit 0
          fi

          pick_wall() {
            local w=""
            if command -v awww >/dev/null 2>&1; then
              w=$(awww query 2>/dev/null | grep -oE '/[^ ]+\.(jpg|jpeg|png|webp|JPG|JPEG|PNG|WEBP)' | head -n1 || true)
            fi
            if [ -z "$w" ]; then
              w=$(find "$HOME/Pictures/Wallpapers" -maxdepth 1 \( -type f -o -type l \) \
                \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
                2>/dev/null | head -n1 || true)
            fi
            printf '%s' "$w"
          }

          wall=""
          for _ in 1 2 3 4 5 6; do
            wall=$(pick_wall)
            [ -n "$wall" ] && break
            sleep 1
          done

          if [ -n "$wall" ]; then
            ${pkgs.matugen}/bin/matugen --prefer darkness -m dark image "$wall" || true
            bash "$HOME/.config/hypr/scripts/quickshell/wallpaper/matugen_reload.sh" || true
          fi
        '';
      in
      {
        home.packages = with pkgs; [
          matugen
          awww
          swayosd
          cava
          mpvpaper
          satty
          grim
          slurp
          gpu-screen-recorder
          zbar
          playerctl
          pamixer
          brightnessctl
          jq
          imagemagick
          ffmpeg
          inotify-tools
          fortune
          adw-gtk3
          adwaita-icon-theme
          kdePackages.qt6ct
          libsForQt5.qt5ct
          pulseaudio
          socat
          bc
          acpi
          iw
          libnotify
          python3
          thunar
          thunar-volman
          tumbler
          hyprpicker
          cliphist
          qsWrapped
          arcMidnight
        ];

        home.sessionVariables = {
          NIXOS_OZONE_WL = "1";
          QT_QPA_PLATFORMTHEME = "qt6ct";
          TERMINAL = "kitty";
        };

        home.pointerCursor = {
          enable = true;
          gtk.enable = true;
          x11.enable = true;
          package = arcMidnight;
          name = "ArcMidnight-Cursors";
          size = 24;
        };

        dconf.settings."org/gnome/desktop/interface" = {
          color-scheme = "prefer-dark";
          gtk-theme = "adw-gtk3-dark";
          icon-theme = "Adwaita";
          cursor-theme = "ArcMidnight-Cursors";
          cursor-size = 24;
          font-name = "Inter 11";
          document-font-name = "Inter 11";
          monospace-font-name = "JetBrainsMono Nerd Font 11";
        };

        gtk = {
          enable = true;
          font = {
            name = "Inter";
            size = 11;
          };
          gtk3.extraCss = gtkCssImport;
          gtk4.extraCss = gtkCssImport;
          gtk3.extraConfig = {
            gtk-application-prefer-dark-theme = 1;
            gtk-theme-name = "adw-gtk3-dark";
            gtk-font-name = "Inter 11";
          };
          gtk4.extraConfig = {
            gtk-application-prefer-dark-theme = 1;
            gtk-font-name = "Inter 11";
          };
        };

        qt = {
          enable = true;
          platformTheme.name = "qt6ct";
        };

        services.swayosd = {
          enable = true;
          topMargin = 0.9;
          stylePath = "${config.home.homeDirectory}/.config/swayosd/style.css";
        };

        programs.kitty.extraConfig = lib.mkForce ''
          font_family JetBrains Mono
          font_size 13.0
          bold_font auto
          italic_font auto
          bold_italic_font auto
          cursor_trail 1
          background_opacity 1.0
          confirm_os_window_close 0
          scrollback_lines 2000
          wheel_scroll_min_lines 1
          enable_audio_bell no
          hide_window_decorations yes
          window_padding_width 4
          include ${config.home.homeDirectory}/.cache/matugen/kitty-colors.conf
          include /tmp/kitty-matugen-colors.conf
        '';

        systemd.user.services.quickshell = {
          Unit = {
            Description = "Serpantinum Quickshell desktop";
            PartOf = [ "graphical-session.target" ];
            After = [ "graphical-session.target" ];
          };
          Service = {
            ExecStartPre = "-${pkgs.procps}/bin/pkill -f /bin/quickshell";
            ExecStart = "${qsWrapped}/bin/qs -p ${config.home.homeDirectory}/.config/hypr/scripts/quickshell/Shell.qml";
            Restart = "on-failure";
            RestartSec = "1s";
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };

        systemd.user.services.serpantinum-matugen-seed = {
          Unit = {
            Description = "Seed matugen colors if /tmp files are missing";
            After = [ "graphical-session.target" ];
            PartOf = [ "graphical-session.target" ];
          };
          Service = {
            Type = "oneshot";
            ExecStart = "${seedMatugen}";
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };

        xdg.configFile = {
          # Surface-dots left regular files / theme symlinks here.
          "gtk-3.0/gtk.css".force = true;
          "gtk-3.0/settings.ini".force = true;
          "gtk-4.0/gtk.css".force = true;
          "hypr/scripts" = {
            source = hyprScripts;
            recursive = true;
            force = true;
          };
          "matugen" = {
            source = matugenCfg;
            recursive = true;
            force = true;
          };
        };

        # checkLinkTargets runs before writeBoundary; drop leftover surface-dots
        # files that backupFileExtension cannot move (theme symlinks, script dir).
        home.activation.cleanupSurfaceDotsCollisions = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
          rm -f "$HOME/.config/gtk-3.0/gtk.css" "$HOME/.config/gtk-3.0/settings.ini"
          rm -f "$HOME/.config/gtk-4.0/gtk.css" "$HOME/.config/gtk-4.0/gtk-dark.css"
          rm -rf "$HOME/.config/gtk-4.0/assets"

          if [ -d "$HOME/.config/hypr/scripts" ] && [ ! -L "$HOME/.config/hypr/scripts" ]; then
            rm -rf "$HOME/.config/hypr/scripts"
          fi

          # Bare `qs` loads this path; leftover surface-dots config would show a second bar.
          rm -rf "$HOME/.config/quickshell"
        '';

        home.file."Pictures/Wallpapers/IUBepkp.jpeg".source = ./wallpaper-assets/IUBepkp.jpeg;
        home.file."Pictures/Wallpapers/nier.webp".source = ./wallpaper-assets/nier.webp;
        home.file."Pictures/Wallpapers/car.png".source = ./wallpaper-assets/car.png;
        home.file."Pictures/Wallpapers/leaf.png".source = ./wallpaper-assets/leaf.png;

        home.activation.seedSerpantinum = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          seed_if_needed() {
            local path="$1"
            local content="$2"
            if [ ! -e "$path" ] || [ -L "$path" ]; then
              mkdir -p "$(dirname "$path")"
              rm -f "$path"
              printf '%s\n' "$content" > "$path"
              chmod u+w "$path"
            fi
          }

          seed_if_needed "$HOME/.config/hypr/settings.json" ${lib.escapeShellArg seedSettings}
          ${pkgs.jq}/bin/jq --argjson kb ${lib.escapeShellArg keybindsJson} \
            '.keybinds = $kb' "$HOME/.config/hypr/settings.json" > "$HOME/.config/hypr/settings.json.tmp" \
            && mv "$HOME/.config/hypr/settings.json.tmp" "$HOME/.config/hypr/settings.json"
          chmod u+w "$HOME/.config/hypr/settings.json"
          seed_if_needed "$HOME/.config/hypr/colors.lua" ${lib.escapeShellArg ''
            return {
              active_border = "rgba(89b4faee)",
              inactive_border = "rgba(45475aaa)",
            }
          ''}
          mkdir -p "$HOME/.cache/matugen" "$HOME/.config/swayosd" \
            "$HOME/.config/qt5ct/colors" "$HOME/.config/qt6ct/colors" \
            "$HOME/.config/qt5ct/qss" "$HOME/.config/qt6ct/qss" \
            "$HOME/.config/cava" "$HOME/Pictures/Screenshots" "$HOME/Videos/Recordings"
          seed_if_needed "$HOME/.config/swayosd/style.css" "window { border-radius: 8px; }"
        '';
      };
  };
}
