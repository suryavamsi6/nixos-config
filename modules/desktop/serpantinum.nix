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
        hyprlandPkg = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
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
              (
                  'property bool isDesktop: false',
                  'property bool isDesktop: false\n            property bool hasPowerSupply: false',
              ),
              (
                  'if (barWindow.batStatus !== data.status) barWindow.batStatus = data.status;',
                  'if (barWindow.batStatus !== data.status) barWindow.batStatus = data.status;\n                                if (barWindow.hasPowerSupply !== !!data.present) barWindow.hasPowerSupply = !!data.present;',
              ),
              (
                  'color: barWindow.isDesktop ? mocha.red : barWindow.batDynamicColor;',
                  'color: !barWindow.hasPowerSupply ? mocha.red : barWindow.batDynamicColor;',
              ),
              (
                  'color: barWindow.isDesktop ? Qt.lighter(mocha.red, 1.3) : Qt.lighter(barWindow.batDynamicColor, 1.3);',
                  'color: !barWindow.hasPowerSupply ? Qt.lighter(mocha.red, 1.3) : Qt.lighter(barWindow.batDynamicColor, 1.3);',
              ),
              (
                  'property real targetWidth: barWindow.isDesktop ? barWindow.s(34) : batLayoutRow.implicitWidth + barWindow.s(24)',
                  'property real targetWidth: !barWindow.hasPowerSupply ? barWindow.s(34) : batLayoutRow.implicitWidth + barWindow.s(24)',
              ),
              (
                  'text: barWindow.isDesktop ? "" : barWindow.batIcon;',
                  'text: !barWindow.hasPowerSupply ? "" : barWindow.batIcon;',
              ),
              (
                  'visible: !barWindow.isDesktop\n                                        text: barWindow.batPercent;',
                  'visible: barWindow.hasPowerSupply\n                                        text: barWindow.batPercent;',
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

        patchBatteryPopup = pkgs.writeText "patch-serpantinum-battery-popup.py" ''
          from pathlib import Path
          import sys
          import textwrap

          p = Path(sys.argv[1])
          t = p.read_text()
          replacements = [
              (
                  '    property string batStatus: "Unknown"\n    property string powerProfile: "balanced"',
                  '    property string batStatus: "Unknown"\n    property string batKind: "none"\n    property bool hasPowerSupply: false\n    property bool hasBrightness: false\n    property bool hasPowerProfiles: false\n    property string powerProfile: "balanced"',
              ),
              (
                  '                            property bool isDangerState: !window.isCharging && window.batCapacity < 15',
                  '                            property bool isDangerState: window.hasPowerSupply && !window.isCharging && window.batCapacity < 15',
              ),
              (
                  '                                        text: window.isCharging ? "󰂄" : (window.batCapacity > 20 ? "󰁹" : "󰂃")',
                  '                                        text: window.batKind === "ups" ? (window.isCharging ? "󰂄" : "󰚥") : (window.isCharging ? "󰂄" : (window.batCapacity > 20 ? "󰁹" : "󰂃"))',
              ),
              (
                  '                                        text: window.batStatus.toUpperCase()',
                  '                                        text: (window.batKind === "ups" ? "UPS · " : "") + window.batStatus.toUpperCase()',
              ),
              (
                  '                                Layout.preferredHeight: window.s(96)',
                  '                                Layout.preferredHeight: window.hasBrightness ? window.s(96) : window.s(54)',
              ),
              (
                  '                                    // Brightness Slider\n                                    RowLayout {\n                                        Layout.fillWidth: true\n                                        spacing: window.s(15)',
                  '                                    // Brightness Slider\n                                    RowLayout {\n                                        visible: window.hasBrightness\n                                        Layout.fillWidth: true\n                                        spacing: window.s(15)',
              ),
              (
                  '                            // 3. POWER PROFILES DOCK\n                            Rectangle {\n                                Layout.fillWidth: true\n                                Layout.preferredHeight: window.s(54)',
                  '                            // 3. POWER PROFILES DOCK\n                            Rectangle {\n                                visible: window.hasPowerProfiles\n                                Layout.fillWidth: true\n                                Layout.preferredHeight: window.hasPowerProfiles ? window.s(54) : 0',
              ),
              (
                  '            "cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -n1 || echo \'0\'; " +\n            "cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -n1 || echo \'Unknown\'; " +\n            "powerprofilesctl get 2>/dev/null || echo \'balanced\'; " +',
                  '            "powerprofilesctl get 2>/dev/null || echo \'balanced\'; " +',
              ),
              (
                  '                let lines = this.text.trim().split("\\n");\n                if (lines.length >= 6) {\n                    if (window.batCapacity !== parseInt(lines[0])) {\n                        window.batCapacity = parseInt(lines[0]);\n                        window.animCapacity = window.batCapacity;\n                    }\n                    window.batStatus = lines[1];\n                    window.powerProfile = lines[2];',
                  '                let lines = this.text.trim().split("\\n");\n                if (lines.length >= 4) {\n                    window.powerProfile = lines[0];',
              ),
              (
                  '                    let upParts = lines[3].split("h ");',
                  '                    let upParts = lines[1].split("h ");',
              ),
              (
                  '                        let volParts = (lines[4] || "0 on").trim().split(" ");',
                  '                        let volParts = (lines[2] || "0 on").trim().split(" ");',
              ),
              (
                  '                        window.sysBrightness = parseInt(lines[5]) || 0;',
                  '                        window.sysBrightness = parseInt(lines[3]) || 0;',
              ),
              (
                  '        onTriggered: sysPoller.running = true',
                  '        onTriggered: { sysPoller.running = true; batFetch.running = true; }',
              ),
          ]
          for old, new in replacements:
              if old not in t:
                  raise SystemExit(f"BatteryPopup patch missing string:\\n{old}")
              t = t.replace(old, new, 1)

          marker = "    Process {\n        id: sysPoller"
          insert = textwrap.dedent(
              """
              Process {
                  id: featureDetect
                  running: true
                  command: ["bash", "-c", "if ls /sys/class/backlight/*/brightness >/dev/null 2>&1; then echo 1; else echo 0; fi; if systemctl is-active --quiet power-profiles-daemon; then echo 1; else echo 0; fi"]
                  stdout: StdioCollector {
                      onStreamFinished: {
                          let lines = this.text.trim().split("\\n");
                          if (lines.length >= 2) {
                              window.hasBrightness = lines[0] === "1";
                              window.hasPowerProfiles = lines[1] === "1";
                          }
                      }
                  }
              }

              Process {
                  id: batFetch
                  command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/watchers/battery_fetch.sh"]
                  running: true
                  stdout: StdioCollector {
                      onStreamFinished: {
                          let txt = this.text.trim();
                          if (txt === "") return;
                          try {
                              let data = JSON.parse(txt);
                              let pct = parseInt(data.percent) || 0;
                              if (window.batCapacity !== pct) {
                                  window.batCapacity = pct;
                                  window.animCapacity = pct;
                              }
                              if (data.status) window.batStatus = data.status;
                              window.batKind = data.kind || "none";
                              window.hasPowerSupply = !!data.present;
                          } catch (e) {}
                      }
                  }
              }
              """
          ).strip("\n")
          insert = "\n".join(("    " + line) if line else line for line in insert.split("\n")) + "\n\n"
          if marker not in t:
              raise SystemExit("BatteryPopup patch missing sysPoller marker")
          t = t.replace(marker, insert + marker, 1)
          p.write_text(t)
        '';

        # The MAG 341C OLED is an external display, so it has no kernel
        # backlight device. Prefer a laptop backlight when one exists, then
        # fall back to the monitor's DDC/CI brightness VCP (0x10).
        # DDC is slow (~0.7s) and exclusive per I2C bus — serialize with flock,
        # pin the bus, and cache the last value so the popup poller stays fast
        # and concurrent get/set from Quickshell do not reset the slider to 0.
        brightnessControl = pkgs.writeShellScript "serpantinum-brightness" ''
          set -euo pipefail

          ddcutil=${pkgs.ddcutil}/bin/ddcutil
          brightnessctl=${pkgs.brightnessctl}/bin/brightnessctl
          flock=${pkgs.util-linux}/bin/flock
          hyprctl=${hyprlandPkg}/bin/hyprctl
          jq=${pkgs.jq}/bin/jq
          cache_dir="''${XDG_CACHE_HOME:-$HOME/.cache}/serpantinum"
          bus_file="$cache_dir/ddc-bus"
          value_file="$cache_dir/brightness"
          lock_file="$cache_dir/ddc.lock"
          mkdir -p "$cache_dir"

          backlight=$(find /sys/class/backlight -mindepth 1 -maxdepth 1 -type d -print -quit 2>/dev/null || true)

          hdr_get_raw() {
            local value
            value=$("$hyprctl" monitors -j 2>/dev/null \
              | "$jq" -er '.[] | select(.name == "HDMI-A-2" and .colorManagementPreset == "hdr") | (.sdrBrightness * 100 | round)') || return 1
            [ "$value" -ge 0 ] && [ "$value" -le 100 ] || return 1
            printf '%s\n' "$value"
          }

          hdr_set_raw() {
            local percent="$1" multiplier
            multiplier=$(awk -v value="$percent" 'BEGIN { printf "%.2f", value / 100 }')
            "$hyprctl" eval "hl.monitor({ output = \"HDMI-A-2\", sdrbrightness = $multiplier })" >/dev/null
          }

          read_cache() {
            local value
            [ -f "$value_file" ] || return 1
            value=$(tr -cd '0-9' <"$value_file")
            [ -n "$value" ] || return 1
            printf '%s\n' "$value"
          }

          write_cache() {
            printf '%s\n' "$1" >"$value_file"
          }

          ddc_bus() {
            local bus
            if [ -f "$bus_file" ]; then
              bus=$(tr -cd '0-9' <"$bus_file")
              if [ -n "$bus" ] && [ -e "/dev/i2c-$bus" ]; then
                printf '%s\n' "$bus"
                return 0
              fi
            fi
            bus=$("$ddcutil" detect --brief 2>/dev/null | sed -n 's|.*/dev/i2c-\([0-9][0-9]*\).*|\1|p' | head -n1)
            [ -n "$bus" ] || return 1
            printf '%s\n' "$bus" >"$bus_file"
            printf '%s\n' "$bus"
          }

          ddc_get_raw() {
            local bus result current maximum
            bus=$(ddc_bus) || return 1
            result=$("$ddcutil" --bus "$bus" getvcp 10 2>/dev/null) || return 1
            current=$(sed -n 's/.*current value = [[:space:]]*\([0-9][0-9]*\), max value = [[:space:]]*\([0-9][0-9]*\).*/\1/p' <<<"$result" | head -n1)
            maximum=$(sed -n 's/.*current value = [[:space:]]*\([0-9][0-9]*\), max value = [[:space:]]*\([0-9][0-9]*\).*/\2/p' <<<"$result" | head -n1)
            [ -n "$current" ] && [ -n "$maximum" ] && [ "$maximum" -gt 0 ] || return 1
            printf '%s\n' "$((current * 100 / maximum))"
          }

          ddc_set_raw() {
            local bus percent="$1"
            bus=$(ddc_bus) || return 1
            # MAG 341C reports max=100, so percent maps 1:1 onto VCP 0x10.
            "$ddcutil" --bus "$bus" setvcp 10 "$percent" >/dev/null
          }

          case "''${1:-}" in
            available)
              if [ -n "$backlight" ]; then
                exit 0
              fi
              if value=$(hdr_get_raw); then
                write_cache "$value"
                exit 0
              fi
              (
                "$flock" -w 5 9 || exit 1
                value=$(ddc_get_raw) || exit 1
                write_cache "$value"
              ) 9>"$lock_file"
              ;;
            get)
              if [ -n "$backlight" ]; then
                "$brightnessctl" -m | awk -F, '{print substr($4, 1, length($4)-1)}'
                exit 0
              fi
              # The MAG 341C locks its hardware Brightness control while it
              # receives HDR. Hyprland's SDR brightness multiplier is the
              # effective desktop-luminance control in that mode.
              if value=$(hdr_get_raw); then
                write_cache "$value"
                printf '%s\n' "$value"
                exit 0
              fi
              # DDC is the source of truth. The cache is only a fallback for
              # transient monitor/I2C errors; otherwise a stale value makes
              # the popup snap back after the user moves the slider.
              if value=$(
                (
                  "$flock" -w 5 9 || exit 1
                  ddc_get_raw
                ) 9>"$lock_file"
              ); then
                write_cache "$value"
                printf '%s\n' "$value"
              elif value=$(read_cache); then
                printf '%s\n' "$value"
              else
                exit 1
              fi
              ;;
            set)
              percent="''${2:-}"
              case "$percent" in
                ""|*[!0-9]*) exit 2 ;;
              esac
              percent=$((percent > 100 ? 100 : percent))
              if [ -n "$backlight" ]; then
                "$brightnessctl" set "$percent%"
                exit 0
              fi
              if hdr_get_raw >/dev/null; then
                write_cache "$percent"
                hdr_set_raw "$percent"
                exit 0
              fi
              # Optimistic cache so the popup poller never flashes back to 0
              # while a slow DDC write is still in flight.
              write_cache "$percent"
              (
                "$flock" -w 5 9 || exit 1
                ddc_set_raw "$percent"
              ) 9>"$lock_file" || true
              ;;
            *)
              echo "Usage: $0 {available|get|set PERCENT}" >&2
              exit 2
              ;;
          esac
        '';

        patchBatteryBrightness = pkgs.writeText "patch-serpantinum-battery-brightness.py" ''
          from pathlib import Path
          import sys
          import textwrap

          p = Path(sys.argv[1])
          t = p.read_text()
          replacements = [
              (
                  'command: ["bash", "-c", "if ls /sys/class/backlight/*/brightness >/dev/null 2>&1; then echo 1; else echo 0; fi; if systemctl is-active --quiet power-profiles-daemon; then echo 1; else echo 0; fi"]',
                  'command: ["bash", "-c", "if ~/.config/hypr/scripts/quickshell/watchers/brightness_control.sh available; then echo 1; else echo 0; fi; if systemctl is-active --quiet power-profiles-daemon; then echo 1; else echo 0; fi"]',
              ),
              (
                  "brightnessctl -m 2>/dev/null | awk -F, '{print substr($4, 1, length($4)-1)}' || echo '0'",
                  "~/.config/hypr/scripts/quickshell/watchers/brightness_control.sh get 2>/dev/null || echo '0'",
              ),
              (
                  'Timer { id: briSyncDelay; interval: 800; onTriggered: window.isDraggingBri = false; triggeredOnStart: true; }',
                  'Timer { id: briSyncDelay; interval: 1500; onTriggered: window.isDraggingBri = false; }',
              ),
              (
                  'Layout.preferredHeight: window.hasBrightness ? window.s(96) : window.s(54)',
                  'Layout.preferredHeight: window.hasBrightness ? window.s(110) : window.s(54)',
              ),
          ]
          for old, new in replacements:
              if old not in t:
                  raise SystemExit(f"Battery brightness patch missing string:\\n{old}")
              t = t.replace(old, new, 1)

          marker_start = "                                    // Brightness Slider\n"
          marker_end = "                                    // Volume Slider\n"
          if marker_start not in t or marker_end not in t:
              raise SystemExit("Battery brightness slider markers missing")
          start = t.index(marker_start)
          end = t.index(marker_end)
          new_bri = textwrap.dedent(
              """\
                                    // Brightness Slider (DDC/CI via brightness_control.sh)
                                    RowLayout {
                                        z: 20
                                        visible: window.hasBrightness
                                        Layout.fillWidth: true
                                        spacing: window.s(15)

                                        Rectangle {
                                            Layout.preferredWidth: window.s(32)
                                            Layout.preferredHeight: window.s(32)
                                            radius: window.s(16)
                                            color: "transparent"
                                            border.color: "transparent"
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                            Behavior on border.color { ColorAnimation { duration: 150 } }
                                            Text {
                                                anchors.centerIn: parent
                                                text: window.sysBrightness > 66 ? "󰃠" : (window.sysBrightness > 33 ? "󰃟" : "󰃞")
                                                font.family: "Iosevka Nerd Font"
                                                font.pixelSize: window.s(22)
                                                color: window.teal
                                            }
                                        }

                                        Item {
                                            id: briSlider
                                            Layout.fillWidth: true
                                            height: window.s(18)

                                            readonly property string briScript: paths.home + "/.config/hypr/scripts/quickshell/watchers/brightness_control.sh"

                                            function applyBri(pct) {
                                                Quickshell.execDetached([briSlider.briScript, "set", String(pct)]);
                                            }

                                            Timer {
                                                id: briDragThrottle
                                                interval: 50
                                                property int targetPct: -1
                                                onTriggered: {
                                                    if (targetPct >= 0) {
                                                        briSlider.applyBri(targetPct);
                                                        targetPct = -1;
                                                    }
                                                }
                                            }

                                            Rectangle {
                                                anchors.fill: parent
                                                radius: window.s(9)
                                                color: window.surface1
                                                border.color: window.surface2
                                                border.width: 1
                                                clip: true

                                                Rectangle {
                                                    height: parent.height
                                                    width: parent.width * (window.sysBrightness / 100)
                                                    radius: window.s(9)
                                                    opacity: briMa.containsMouse ? 1.0 : 0.85
                                                    Behavior on opacity { NumberAnimation { duration: 200 } }
                                                    Behavior on width { enabled: !window.isDraggingBri; NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }
                                                    gradient: Gradient {
                                                        orientation: Gradient.Horizontal
                                                        GradientStop { position: 0.0; color: window.profileStart; Behavior on color { ColorAnimation { duration: 300 } } }
                                                        GradientStop { position: 1.0; color: window.profileEnd; Behavior on color { ColorAnimation { duration: 300 } } }
                                                    }
                                                }
                                            }

                                            MouseArea {
                                                id: briMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onPressed: (mouse) => { briSyncDelay.stop(); window.isDraggingBri = true; updateBri(mouse.x); }
                                                onPositionChanged: (mouse) => { if (pressed) updateBri(mouse.x); }
                                                onReleased: { briSyncDelay.restart(); }
                                                function updateBri(mx) {
                                                    let pct = Math.max(0, Math.min(100, Math.round((mx / width) * 100)));
                                                    window.sysBrightness = pct;
                                                    briDragThrottle.targetPct = pct;
                                                    if (!briDragThrottle.running) briDragThrottle.start();
                                                }
                                            }
                                        }

                                        Text {
                                            Layout.preferredWidth: window.s(40)
                                            horizontalAlignment: Text.AlignRight
                                            text: Math.round(window.sysBrightness) + "%"
                                            font.family: "JetBrains Mono"
                                            font.weight: Font.Bold
                                            font.pixelSize: window.s(13)
                                            color: window.subtext0
                                        }
                                    }

              """
          )
          # Re-indent: textwrap.dedent stripped common indent; block must keep
          # the 36-space RowLayout indent used in BatteryPopup.
          t = t[:start] + new_bri + t[end:]
          p.write_text(t)
        '';

        patchQsManager = pkgs.writeText "patch-serpantinum-qs-manager.py" ''
          from pathlib import Path
          import sys

          p = Path(sys.argv[1])
          t = p.read_text()
          old = 'find "$SRC_DIR" -maxdepth 1 -type f'
          new = 'find -L "$SRC_DIR" -maxdepth 1 -type f'
          if old not in t:
              raise SystemExit("qs_manager find wallpaper scan not found")
          t = t.replace(old, new, 1)
          gif = '-o -iname "*.gif" -o -iname "*.mp4"'
          webp = '-o -iname "*.gif" -o -iname "*.webp" -o -iname "*.mp4"'
          if gif not in t:
              raise SystemExit("qs_manager image filters not found")
          t = t.replace(gif, webp, 1)
          marker = '            if [[ "''${extension,,}" == "webp" ]]; then'
          start = t.find(marker)
          if start == -1:
              raise SystemExit("qs_manager webp conversion block not found")
          end = t.find("\n            fi\n", start)
          if end == -1:
              raise SystemExit("qs_manager webp conversion fi not found")
          t = t[:start] + t[end + len("\n            fi\n") :]
          p.write_text(t)
        '';

        patchBtPanel = pkgs.writeText "patch-serpantinum-bt-panel.py" ''
          from pathlib import Path
          import sys
          import textwrap

          p = Path(sys.argv[1])
          t = p.read_text()
          start = t.index("get_status() {")
          end = t.index('\ncmd="$1"')
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

              toggle_power() {
                  source "$(dirname "''${BASH_SOURCE[0]}")/../watchers/bt_dbus.sh"
                  local ad
                  ad=$(bt_dbus_adapter)
                  if [ -n "$ad" ] && bt_dbus_bool "$ad" org.bluez.Adapter1 Powered; then
                      bt_dbus_set_powered off
                  else
                      bt_dbus_set_powered on
                  fi
                  sleep 0.5
              }

              connect_dev() {
                  source "$(dirname "''${BASH_SOURCE[0]}")/../watchers/bt_dbus.sh"
                  bt_dbus_connect "$1"
              }

              disconnect_dev() {
                  source "$(dirname "''${BASH_SOURCE[0]}")/../watchers/bt_dbus.sh"
                  bt_dbus_disconnect "$1"
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

          bt_dbus_battery_dir() { echo "''${XDG_RUNTIME_DIR:-/tmp}/qs-bt-battery"; }

          bt_dbus_battery_cache_set() {
            local dev="$1" bat="$2" addr dir
            addr=$(bt_dbus_str "$dev" org.bluez.Device1 Address)
            [ -n "$addr" ] && [ -n "$bat" ] || return 0
            dir=$(bt_dbus_battery_dir)
            mkdir -p "$dir"
            printf '%s\n' "$bat" > "$dir/$addr"
          }

          bt_dbus_battery_cache_get() {
            local dev="$1" addr dir age
            addr=$(bt_dbus_str "$dev" org.bluez.Device1 Address)
            dir=$(bt_dbus_battery_dir)
            [ -n "$addr" ] && [ -f "$dir/$addr" ] || return 0
            age=$(($(date +%s) - $(stat -c %Y "$dir/$addr" 2>/dev/null || echo 0)))
            # Stale cache is how ACCENTUM Plus stuck at 10% all afternoon.
            [ "$age" -lt 1200 ] || return 0
            tr -d '[:space:]' < "$dir/$addr"
          }

          bt_dbus_2a19_path() {
            local dev="$1" addr dir cache char uuid
            addr=$(bt_dbus_str "$dev" org.bluez.Device1 Address)
            dir=$(bt_dbus_battery_dir)
            mkdir -p "$dir"
            cache="$dir/''${addr}.char"
            if [ -f "$cache" ]; then
              char=$(tr -d '[:space:]' < "$cache")
              uuid=$(bt_dbus_str "$char" org.bluez.GattCharacteristic1 UUID)
              case "''${uuid,,}" in
                00002a19-0000-1000-8000-00805f9b34fb) echo "$char"; return 0 ;;
              esac
            fi
            while IFS= read -r char; do
              [ -n "$char" ] || continue
              uuid=$(bt_dbus_str "$char" org.bluez.GattCharacteristic1 UUID)
              case "''${uuid,,}" in
                00002a19-0000-1000-8000-00805f9b34fb)
                  printf '%s\n' "$char" > "$cache"
                  echo "$char"
                  return 0
                  ;;
              esac
            done < <(${pkgs.systemd}/bin/busctl --system tree org.bluez --list 2>/dev/null | grep -E "^''${dev}/service[^/]+/char[^/]+$")
          }

          bt_dbus_gatt_level() {
            local char val
            char=$(bt_dbus_2a19_path "$1") || return 0
            [ -n "$char" ] || return 0
            val=$(${pkgs.systemd}/bin/busctl --system --timeout=3 call org.bluez "$char" org.bluez.GattCharacteristic1 ReadValue 'a{sv}' 0 2>/dev/null) || return 0
            echo "$val" | awk '/^ay / { print $NF; exit }'
          }

          bt_dbus_battery() {
            local dev="$1" bat
            bat=$(bt_dbus_byte "$dev" org.bluez.Battery1 Percentage)
            if [ -z "$bat" ]; then
              bat=$(bt_dbus_gatt_level "$dev")
            fi
            if [ -n "$bat" ]; then
              bt_dbus_battery_cache_set "$dev" "$bat"
              echo "$bat"
              return 0
            fi
            bt_dbus_battery_cache_get "$dev"
          }

          bt_dbus_is_audio() {
            local icon uuids
            icon=$(bt_dbus_str "$1" org.bluez.Device1 Icon)
            case "$icon" in
              audio-headset|audio-headphones|audio-card) return 0 ;;
            esac
            uuids=$(bt_dbus_prop "$1" org.bluez.Device1 UUIDs)
            echo "$uuids" | grep -q 0000110b-0000-1000-8000-00805f9b34fb
          }

          # Dual-mode headsets expose 0x2A19 only on LE. Snapshot once, then
          # drop LE so A2DP is not sharing the radio. Do not poll
          # Bearer.LE1.Connect — that scans if idle. Cooldown stops the
          # popup's 3s refresh from reconnecting LE in a loop.
          bt_dbus_refresh_headset_battery() {
            local dev="$1" lock bat i age addr dir stamp
            bt_dbus_is_audio "$dev" || return 0
            [ -n "$(bt_dbus_prop "$dev" org.bluez.Bearer.LE1 Connected)" ] || return 0
            addr=$(bt_dbus_str "$dev" org.bluez.Device1 Address)
            dir=$(bt_dbus_battery_dir)
            mkdir -p "$dir"
            stamp="$dir/''${addr}.le-try"
            if [ -f "$stamp" ]; then
              age=$(($(date +%s) - $(stat -c %Y "$stamp" 2>/dev/null || echo 0)))
              [ "$age" -lt 60 ] && return 0
            fi
            lock="''${XDG_RUNTIME_DIR:-/tmp}/qs-bt-battery.lock"
            if [ -d "$lock" ]; then
              age=$(($(date +%s) - $(stat -c %Y "$lock" 2>/dev/null || echo 0)))
              [ "$age" -gt 30 ] && rmdir "$lock" 2>/dev/null || true
            fi
            mkdir "$lock" 2>/dev/null || return 0
            touch "$stamp"
            if ! bt_dbus_bool "$dev" org.bluez.Bearer.LE1 Connected; then
              ${pkgs.systemd}/bin/busctl --system --timeout=8 call org.bluez "$dev" org.bluez.Bearer.LE1 Connect >/dev/null 2>&1 || true
            fi
            bat=""
            i=0
            while [ "$i" -lt 12 ]; do
              i=$((i + 1))
              bat=$(bt_dbus_byte "$dev" org.bluez.Battery1 Percentage)
              [ -z "$bat" ] && bat=$(bt_dbus_gatt_level "$dev")
              if [ -n "$bat" ]; then
                bt_dbus_battery_cache_set "$dev" "$bat"
                break
              fi
              sleep 0.4
            done
            ${pkgs.systemd}/bin/busctl --system --timeout=3 call org.bluez "$dev" org.bluez.Bearer.LE1 Disconnect >/dev/null 2>&1 || true
            rmdir "$lock" 2>/dev/null || true
          }

          # Powered=false rfkill-softblocks MediaTek; bluetoothctl power on then
          # fails with 0x03. Unblock first. Never invoke bluetoothctl here.
          bt_dbus_set_powered() {
            local ad
            ad=$(bt_dbus_adapter)
            [ -n "$ad" ] || return 1
            if [ "$1" = on ]; then
              ${pkgs.util-linux}/bin/rfkill unblock bluetooth >/dev/null 2>&1 || true
              ${pkgs.systemd}/bin/busctl --system set-property org.bluez "$ad" org.bluez.Adapter1 Powered b true
            else
              ${pkgs.systemd}/bin/busctl --system set-property org.bluez "$ad" org.bluez.Adapter1 Powered b false
            fi
          }
          bt_dbus_device_path() {
            local ad mac="$1"
            ad=$(bt_dbus_adapter)
            [ -n "$ad" ] || return 1
            echo "$ad/dev_''${mac//:/_}"
          }
          bt_dbus_connect() {
            local path
            path=$(bt_dbus_device_path "$1") || return 1
            ${pkgs.systemd}/bin/busctl --system call org.bluez "$path" org.bluez.Device1 Connect >/dev/null
            bt_dbus_refresh_headset_battery "$path" || true
          }
          bt_dbus_disconnect() {
            local path
            path=$(bt_dbus_device_path "$1") || return 1
            ${pkgs.systemd}/bin/busctl --system call org.bluez "$path" org.bluez.Device1 Disconnect >/dev/null
          }

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
                  bat=$(bt_dbus_battery "$dev")
                  if [ -z "$bat" ] && bt_dbus_is_audio "$dev"; then
                    bt_dbus_refresh_headset_battery "$dev" >/dev/null 2>&1 &
                  fi
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

        # Laptop BAT* first, else UPower UPS (this desktop is an APC Back-UPS
        # RS 1500G-IN on hiddev; it never appears under /sys/class/power_supply).
        batteryFetch = pkgs.writeText "battery_fetch.sh" ''
          #!/usr/bin/env bash
          icon_for() {
            local percent=$1 status=$2
            if [ "$status" = "Charging" ] || [ "$status" = "Full" ]; then
              if [ "$percent" -ge 90 ]; then echo "󰂅"
              elif [ "$percent" -ge 80 ]; then echo "󰂋"
              elif [ "$percent" -ge 60 ]; then echo "󰂊"
              elif [ "$percent" -ge 40 ]; then echo "󰢞"
              elif [ "$percent" -ge 20 ]; then echo "󰂆"
              else echo "󰢜"; fi
            else
              if [ "$percent" -ge 90 ]; then echo "󰁹"
              elif [ "$percent" -ge 80 ]; then echo "󰂂"
              elif [ "$percent" -ge 70 ]; then echo "󰂁"
              elif [ "$percent" -ge 60 ]; then echo "󰂀"
              elif [ "$percent" -ge 50 ]; then echo "󰁿"
              elif [ "$percent" -ge 40 ]; then echo "󰁾"
              elif [ "$percent" -ge 30 ]; then echo "󰁽"
              elif [ "$percent" -ge 20 ]; then echo "󰁼"
              elif [ "$percent" -ge 10 ]; then echo "󰁻"
              else echo "󰁺"; fi
            fi
          }
          emit() {
            local percent=$1 status=$2 kind=$3 present=$4
            percent=''${percent%.*}
            percent=''${percent:-0}
            ${pkgs.jq}/bin/jq -n -c \
              --arg percent "$percent" \
              --arg status "$status" \
              --arg icon "$(icon_for "$percent" "$status")" \
              --arg kind "$kind" \
              --argjson present "$present" \
              '{percent:$percent,status:$status,icon:$icon,kind:$kind,present:$present}'
          }
          up_prop() {
            ${pkgs.systemd}/bin/busctl --system get-property org.freedesktop.UPower \
              "$1" org.freedesktop.UPower.Device "$2" 2>/dev/null | awk '{print $2; exit}'
          }
          up_state_name() {
            case $1 in
              1|5) echo Charging ;;
              4) echo Full ;;
              2|6) echo "On battery" ;;
              3) echo Empty ;;
              *) echo Unknown ;;
            esac
          }
          try_upower() {
            local path=$1 present type pct state kind
            present=$(up_prop "$path" IsPresent)
            type=$(up_prop "$path" Type)
            [ "$present" = true ] || return 1
            [ "$type" = 2 ] || [ "$type" = 3 ] || return 1
            pct=$(up_prop "$path" Percentage)
            state=$(up_prop "$path" State)
            if [ "$type" = 3 ]; then kind=ups; else kind=battery; fi
            emit "$pct" "$(up_state_name "$state")" "$kind" true
          }

          shopt -s nullglob
          for bat in /sys/class/power_supply/BAT*; do
            if [ -r "$bat/capacity" ]; then
              emit "$(LC_ALL=C cat "$bat/capacity")" "$(LC_ALL=C cat "$bat/status")" battery true
              exit 0
            fi
          done

          while IFS= read -r path; do
            case $path in
              */DisplayDevice) continue ;;
            esac
            try_upower "$path" && exit 0
          done < <(${pkgs.upower}/bin/upower -e)

          try_upower /org/freedesktop/UPower/devices/DisplayDevice && exit 0
          emit 0 Offline none false
        '';

        hyprScripts = pkgs.runCommand "serpantinum-hypr-scripts" { } ''
          mkdir -p $out
          cp -a ${dots}/config/sessions/hyprland/scripts/. $out/
          chmod -R u+w $out
          cp ${appFetcher} $out/quickshell/applauncher/app_fetcher.py
          cp ${btDbus} $out/quickshell/watchers/bt_dbus.sh
          cp ${btFetch} $out/quickshell/watchers/bt_fetch.sh
          cp ${batteryFetch} $out/quickshell/watchers/battery_fetch.sh
          cp ${brightnessControl} $out/quickshell/watchers/brightness_control.sh
          chmod +x $out/quickshell/watchers/bt_dbus.sh $out/quickshell/watchers/bt_fetch.sh $out/quickshell/watchers/battery_fetch.sh $out/quickshell/watchers/brightness_control.sh

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
                           'barWindow.timeStr = Qt.formatDateTime(d, "h:mm AP");'

          substituteInPlace $out/quickshell/calendar/CalendarPopup.qml \
            --replace-fail 'text: Qt.formatTime(window.currentTime, "HH:mm")' \
                           'text: Qt.formatTime(window.currentTime, "h:mm")'
          ${pkgs.python3}/bin/python3 ${patchTopBar} $out/quickshell/TopBar.qml
          ${pkgs.python3}/bin/python3 ${patchBatteryPopup} $out/quickshell/battery/BatteryPopup.qml
          ${pkgs.python3}/bin/python3 ${patchBatteryBrightness} $out/quickshell/battery/BatteryPopup.qml
          ${pkgs.python3}/bin/python3 ${patchBtPanel} $out/quickshell/network/bluetooth_panel_logic.sh
          ${pkgs.python3}/bin/python3 ${patchQsManager} $out/qs_manager.sh

          substituteInPlace $out/quickshell/network/NetworkPopup.qml \
            --replace-fail 'nodes.push({ id: "bat_" + obj.mac, name: (obj.battery || "0") + "%", icon: "󰥉", action: "Battery", isInfoNode: true, isActionable: false, parentIndex: cIndex });' \
                           'if (obj.battery) { nodes.push({ id: "bat_" + obj.mac, name: obj.battery + "%", icon: "󰥉", action: "Battery", isInfoNode: true, isActionable: false, parentIndex: cIndex }); }'

          substituteInPlace $out/qs_manager.sh \
            --replace-fail '{ echo "scan on"; sleep infinity; } | stdbuf -oL bluetoothctl > "$BT_SCAN_LOG" 2>&1 &' \
                           ': # bluetoothctl scan on drops A2DP on MediaTek; paired devices still list over D-Bus' \
            --replace-fail '(bluetoothctl scan off > /dev/null 2>&1) &' \
                           ':'

          substituteInPlace $out/workspaces.sh \
            --replace-fail '(timeout 2 bluetoothctl scan off > /dev/null 2>&1) &' \
                           ':'

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
            (mkBind "SUPER" "E" "exec" "nautilus")
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
            (mkBind "SUPER" "TAB" "exec" "workspace overview")
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
          ddcutil
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
            # Steam / nmcli / pactl waiters are in this cgroup when started
            # from the bar. Do not wait 90s for them on poweroff.
            KillMode = "control-group";
            TimeoutStopSec = "5s";
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
