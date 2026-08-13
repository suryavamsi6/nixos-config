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

        hyprScripts = pkgs.runCommand "serpantinum-hypr-scripts" { } ''
          mkdir -p $out
          cp -a ${dots}/config/sessions/hyprland/scripts/. $out/
          chmod -R u+w $out

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

          substituteInPlace $out/quickshell/calendar/weather.sh \
            --replace-fail 'if [ -f "$ENV_FILE" ]; then
    export $(grep -v '\''^#'\'' "$ENV_FILE" | xargs)
fi' \
                           'if [ -f "$ENV_FILE" ] && grep -qE '\''^[[:space:]]*OPENWEATHER_'\'' "$ENV_FILE"; then
    set -a
    source "$ENV_FILE" >/dev/null
    set +a
fi'

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

        seedSettings = builtins.toJSON { uiScale = 1.0; };

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
        };

        gtk = {
          enable = true;
          gtk3.extraCss = gtkCssImport;
          gtk4.extraCss = gtkCssImport;
          gtk3.extraConfig = {
            gtk-application-prefer-dark-theme = 1;
            gtk-theme-name = "adw-gtk3-dark";
          };
          gtk4.extraConfig = {
            gtk-application-prefer-dark-theme = 1;
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
          font_size 16.0
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
