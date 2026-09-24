# MangoWM — NixOS session and Home Manager configuration
{ lib, ... }:
let
  mangoWlOnly = pkgs: pkgs.mango.overrideAttrs (old: {
    pname = "mango-wl-only";
    version = "0.16.3";
    src = pkgs.fetchFromGitHub {
      owner = "mangowm";
      repo = "mango";
      rev = "f637c0c81166a801861fa0c1d49c8f3c31a3fc84";
      hash = "sha256-F9NP/KoCEl/2XQEq/WDaN92rsATyPFz1m3Vcot23FxY=";
    };
    buildInputs = lib.filter (input: input != pkgs.scenefx) old.buildInputs;
  });
in
{
  options.flake.modules.nixos.mango = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { pkgs, ... }:
      {
        # The pinned nixpkgs module provides the package, session entry, and
        # WLR/GTK portal routing. These two options are intentionally explicit:
        # nixpkgs' module does not enable them for us.
        programs.mango = {
          enable = true;
          package = mangoWlOnly pkgs;
        };
        programs.xwayland.enable = true;
        security.polkit.enable = true;

        environment.sessionVariables = {
          XDG_CURRENT_DESKTOP = "mango";
          NIXOS_OZONE_WL = "1";
          MOZ_ENABLE_WAYLAND = "1";
          GDK_BACKEND = "wayland,x11";
          QT_QPA_PLATFORM = "wayland;xcb";
          NH_OS_FLAKE = "/home/surya/Dotfiles/nixos-config#nixos";
        };

        environment.systemPackages = with pkgs; [
          brightnessctl
          cliphist
          grim
          libnotify
          playerctl
          polkit_gnome
          satty
          slurp
          swayidle
          swaylock
          swayosd
          wl-clipboard
          wtype
          xdg-desktop-portal-gtk
          xrdb
          xprop
          ydotool
        ];
      };
  };

  options.flake.modules.homeManager.mango = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { config, inputs, pkgs, ... }:
      let
        mango = mangoWlOnly pkgs;
        home = config.home.homeDirectory;
        scripts = "${home}/.config/hypr/scripts";
        qs = "${scripts}/qs_manager.sh";
        arcMidnight = pkgs.runCommand "arc-midnight-cursors" { } ''
          mkdir -p $out/share/icons
          ln -s ${pkgs.fetchzip {
            url = "https://github.com/yeyushengfan258/ArcMidnight-Cursors/archive/refs/heads/main.zip";
            hash = "sha256-VgOpt0rukW0+rSkLFoF9O0xO/qgwieAchAev1vjaqPE=";
          }}/dist $out/share/icons/ArcMidnight-Cursors
        '';
        mangoScreenshot = pkgs.writeShellScriptBin "mango-screenshot" ''
          mode="''${1:-fullscreen}"
          dir="${home}/Pictures/Screenshots"
          mkdir -p "$dir"
          file="$dir/$(date +%Y%m%d%H%M%S).png"

          case "$mode" in
            region)
              geometry="$(${pkgs.slurp}/bin/slurp)"
              [ -n "$geometry" ] || exit 0
              ${pkgs.grim}/bin/grim -g "$geometry" "$file"
              ;;
            fullscreen)
              ${pkgs.grim}/bin/grim "$file"
              ;;
            annotate)
              ${pkgs.grim}/bin/grim "$file"
              exec ${pkgs.satty}/bin/satty --filename "$file" \
                --output-filename "$file" --actions-on-enter save-to-file --early-exit
              ;;
            copy)
              tmp="$(mktemp --suffix=.png)"
              trap 'rm -f "$tmp"' EXIT
              ${pkgs.grim}/bin/grim "$tmp"
              ${pkgs.wl-clipboard}/bin/wl-copy < "$tmp"
              ;;
            *)
              echo "usage: mango-screenshot {region|fullscreen|annotate|copy}" >&2
              exit 2
              ;;
          esac
          ${pkgs.libnotify}/bin/notify-send "Screenshot saved" "$file" 2>/dev/null || true
        '';
        mangoIdle = pkgs.writeShellScript "mango-idle" ''
          exec ${pkgs.swayidle}/bin/swayidle -w \
            timeout 120 '${pkgs.brightnessctl}/bin/brightnessctl -s set 10%' \
            resume '${pkgs.brightnessctl}/bin/brightnessctl -r' \
            timeout 180 '${pkgs.systemd}/bin/loginctl lock-session' \
            timeout 360 '${mango}/bin/mmsg dispatch sleep_monitor' \
            resume '${mango}/bin/mmsg dispatch wakeup_monitor' \
            before-sleep '${pkgs.systemd}/bin/loginctl lock-session'
        '';
        mangoPolkit = pkgs.writeShellScript "mango-polkit-agent" ''
          exec ${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1
        '';
        mangoAutostart = pkgs.writeShellScript "mango-autostart" ''
          set -euo pipefail
          ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd \
            DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE \
            NIXOS_OZONE_WL XCURSOR_THEME XCURSOR_SIZE
          ${pkgs.systemd}/bin/systemctl --user reset-failed || true
          ${pkgs.systemd}/bin/systemctl --user start mango-session.target
          ${pkgs.systemd}/bin/systemctl --user start serpantinum.service || true

          start_once() {
            local pattern="$1"
            shift
            if ! ${pkgs.procps}/bin/pgrep -f "$pattern" >/dev/null 2>&1; then
              "$@" >/dev/null 2>&1 &
            fi
          }

          echo 'Xft.dpi: 96' | ${pkgs.xrdb}/bin/xrdb -merge || true
          ${pkgs.xprop}/bin/xprop -root -f _XWAYLAND_GLOBAL_OUTPUT_SCALE 32c \
            -set _XWAYLAND_GLOBAL_OUTPUT_SCALE 1 || true
          start_once 'awww-daemon' ${pkgs.awww}/bin/awww-daemon
          start_once 'quickshell.*Shell.qml' qs -p "${scripts}/quickshell/Shell.qml"
          start_once 'playerctld' ${pkgs.playerctl}/bin/playerctld
          start_once 'blueman-applet' ${pkgs.blueman}/bin/blueman-applet
          start_once 'wl-paste.*--type text.*cliphist store' ${pkgs.wl-clipboard}/bin/wl-paste \
            --type text --watch ${pkgs.cliphist}/bin/cliphist store
          start_once 'wl-paste.*--type image.*cliphist store' ${pkgs.wl-clipboard}/bin/wl-paste \
            --type image --watch ${pkgs.cliphist}/bin/cliphist store
          start_once 'volume_listener.sh' bash "${scripts}/volume_listener.sh"
          start_once 'focus_daemon.py' ${pkgs.python3}/bin/python3 \
            "${scripts}/quickshell/focustime/focus_daemon.py"
        '';
        configText = ''
          # MangoWM 0.16.3 wl-only — dwindle tags trial
          animations=1
          layer_animations=1
          animation_type_open=slide
          animation_type_close=slide
          animation_duration_move=500
          animation_duration_open=400
          animation_duration_tag=350
          animation_duration_close=800
          animation_curve_open=0.46,1.0,0.29,1
          animation_curve_move=0.46,1.0,0.29,1
          animation_curve_tag=0.46,1.0,0.29,1
          animation_curve_close=0.08,0.92,0,1
          # HDR-capable wl-only Mango uses Vulkan without the Scenefx renderer.
          env=WLR_RENDERER,vulkan
          hdr_depth=2

          # Dwindle is the only layout; every tag is explicitly pinned to it.
          circle_layout=dwindle
          tag_num=9

          # MAG 341C OLED. Keep all coordinates non-negative for XWayland.
          monitorrule=name:^HDMI-A-2$,width:3440,height:1440,refresh:175,x:0,y:0,scale:1,hdr:1,hdr_force:1,vrr:0
          monitorrule=name:^HDMI-A-1$,width:3440,height:1440,refresh:175,x:0,y:0,scale:1,hdr:1,hdr_force:1,vrr:0

          # Input and appearance.
          xkb_rules_layout=us
          repeat_rate=25
          repeat_delay=600
          tap_to_click=1
          tap_and_drag=1
          drag_lock=1
          trackpad_natural_scrolling=0
          mouse_natural_scrolling=0
          # Do not let Citrix/remote-session clients inhibit Mango's global shortcuts.
          allow_shortcuts_inhibit=0
          focus_on_activate=1
          focus_cross_monitor=0
          focus_cross_tag=0
          sloppyfocus=1
          warpcursor=1
          gappih=5
          gappiv=5
          gappoh=10
          gappov=10
          borderpx=4
          smartgaps=0
          focused_opacity=1.0
          unfocused_opacity=1.0
          focuscolor=0xc9b890ff
          urgentcolor=0xad401fff

          # Tags 1–9: Super+number switches; Ctrl+number is retained as an alias.
          # Super+Shift+number toggles membership in a second tag.
          # Semantic labels: 1 code, 2 web, 3 chat, 4 media, 5 game, 6 work, 7 files, 8 misc, 9 staging.
          tagrule=id:*,layout_name:dwindle
          tagrule=id:1,layout_name:dwindle
          tagrule=id:2,layout_name:dwindle
          tagrule=id:3,layout_name:dwindle
          tagrule=id:4,layout_name:dwindle
          tagrule=id:5,layout_name:dwindle
          tagrule=id:6,layout_name:dwindle
          tagrule=id:7,layout_name:dwindle
          tagrule=id:8,layout_name:dwindle
          tagrule=id:9,layout_name:dwindle

          # Super is the primary modifier for launchers, apps, and compositor actions.
          bind=ALT,space,spawn_shell,serpantinum msg toggle launcher
          bind=SUPER,space,spawn_shell,serpantinum msg toggle launcher
          bind=SUPER,r,reload_config
          bind=SUPER,q,spawn,ghostty
          bind=SUPER,Return,spawn,ghostty
          bind=ALT,Return,spawn,ghostty
          bind=SUPER,e,spawn_shell,ghostty -e superfile
          bind=SUPER,b,spawn,zen-twilight
          bind=SUPER,p,spawn_shell,hyprpicker -a
          bind=SUPER,c,killclient
          bind=ALT,q,killclient
          bind=ALT,F4,killclient
          bind=SUPER,m,quit
          bind=SUPER,Tab,focusstack,next
          bind=SUPER+SHIFT,Tab,toggleoverview

          # Dwindle focus and client exchange bindings.
          bind=ALT,left,focusdir,left
          bind=ALT,right,focusdir,right
          bind=ALT,up,focusdir,up
          bind=ALT,down,focusdir,down
          bind=SUPER+SHIFT,left,exchange_client,left
          bind=SUPER+SHIFT,right,exchange_client,right
          bind=SUPER+SHIFT,up,exchange_client,up
          bind=SUPER+SHIFT,down,exchange_client,down
          # Fine movement remains available for floating/helper windows.
          bind=CTRL+SHIFT,up,movewin,+0,-50
          bind=CTRL+SHIFT,down,movewin,+0,+50
          bind=CTRL+SHIFT,left,movewin,-50,+0
          bind=CTRL+SHIFT,right,movewin,+50,+0
          bind=ALT,f,togglefullscreen
          bind=ALT+SHIFT,f,togglefakefullscreen
          bind=ALT,backslash,togglefloating
          bind=ALT,z,toggle_scratchpad
          bind=ALT+SHIFT,left,focusmon,left
          bind=ALT+SHIFT,right,focusmon,right
          bind=SUPER+ALT,left,tagmon,left
          bind=SUPER+ALT,right,tagmon,right
          bind=CTRL+SUPER,left,tagtoleft,0
          bind=CTRL+SUPER,right,tagtoright,0

          # Super+number switches tags; Ctrl+number remains an alternate view binding.
          bind=SUPER,1,view,1,0
          bind=SUPER,2,view,2,0
          bind=SUPER,3,view,3,0
          bind=SUPER,4,view,4,0
          bind=SUPER,5,view,5,0
          bind=SUPER,6,view,6,0
          bind=SUPER,7,view,7,0
          bind=SUPER,8,view,8,0
          bind=SUPER,9,view,9,0
          bind=CTRL,1,view,1,0
          bind=CTRL,2,view,2,0
          bind=CTRL,3,view,3,0
          bind=CTRL,4,view,4,0
          bind=CTRL,5,view,5,0
          bind=CTRL,6,view,6,0
          bind=CTRL,7,view,7,0
          bind=CTRL,8,view,8,0
          bind=CTRL,9,view,9,0
          bind=ALT,1,tag,1,0
          bind=ALT,2,tag,2,0
          bind=ALT,3,tag,3,0
          bind=ALT,4,tag,4,0
          bind=ALT,5,tag,5,0
          bind=ALT,6,tag,6,0
          bind=ALT,7,tag,7,0
          bind=ALT,8,tag,8,0
          bind=ALT,9,tag,9,0
          # Toggle multi-tag membership: press several of these to build a tag mask.
          bind=SUPER+SHIFT,1,toggletag,1
          bind=SUPER+SHIFT,2,toggletag,2
          bind=SUPER+SHIFT,3,toggletag,3
          bind=SUPER+SHIFT,4,toggletag,4
          bind=SUPER+SHIFT,5,toggletag,5
          bind=SUPER+SHIFT,6,toggletag,6
          bind=SUPER+SHIFT,7,toggletag,7
          bind=SUPER+SHIFT,8,toggletag,8
          bind=SUPER+SHIFT,9,toggletag,9
          bind=SUPER,Home,viewtoleft_have_client,0
          bind=SUPER,End,viewtoright_have_client,0

          # Scratchpad, media, lock, screenshots, and Serpantinum panels.
          bind=SUPER,d,spawn_shell,bash ${qs} toggle clipboard
          bind=SUPER,w,spawn_shell,bash ${qs} toggle wallpaper
          bind=SUPER+SHIFT,n,spawn_shell,bash ${qs} toggle network
          bind=SUPER,v,spawn_shell,bash ${qs} toggle volume
          bind=SUPER,s,spawn_shell,bash ${qs} toggle calendar
          bind=SUPER+SHIFT,t,spawn_shell,bash ${qs} toggle focustime
          bind=SUPER,l,spawn,serpantinum lock
          bind=NONE,XF86PowerOff,spawn,serpantinum lock
          bind=ALT,Print,spawn,mango-screenshot fullscreen
          bind=SUPER,Print,spawn,mango-screenshot annotate
          bind=SUPER+SHIFT,Print,spawn,mango-screenshot region
          bind=SUPER+CTRL,Print,spawn,mango-screenshot copy
          bind=NONE,XF86MonBrightnessDown,spawn,swayosd-client --brightness lower
          bind=NONE,XF86MonBrightnessUp,spawn,swayosd-client --brightness raise
          bind=NONE,XF86AudioRaiseVolume,spawn,swayosd-client --output-volume raise
          bind=NONE,XF86AudioLowerVolume,spawn,swayosd-client --output-volume lower
          bind=NONE,XF86AudioMute,spawn,swayosd-client --output-volume mute-toggle
          bind=NONE,XF86AudioMicMute,spawn,swayosd-client --input-volume mute-toggle
          bind=NONE,XF86AudioPlay,spawn,playerctl play-pause
          bind=NONE,XF86AudioPause,spawn,playerctl play-pause
          bind=NONE,XF86AudioNext,spawn,playerctl next
          bind=NONE,XF86AudioPrev,spawn,playerctl previous

          # Mouse focus/drag/resize and horizontal tag scrolling.
          mousebind=SUPER,btn_left,moveresize,curmove
          mousebind=SUPER,btn_right,moveresize,curresize
          axisbind=SUPER,UP,viewtoleft_have_client
          axisbind=SUPER,DOWN,viewtoright_have_client

          # Dialogs and helper windows should not disrupt the dwindle layout.
          windowrule=isfloating:1,width:500,height:300,appid:^blueman-manager$
          windowrule=isfloating:1,width:500,height:600,appid:^nm-connection-editor$
          windowrule=isfloating:1,width:700,height:400,appid:^xdg-desktop-portal-gtk$
          windowrule=isfloating:1,width:1100,height:750,appid:^(org\.kde\.polkit-kde-authentication-agent-1|polkit-gnome-authentication-agent-1|gcr-prompter)$
          windowrule=isfloating:1,width:960,height:720,appid:^(PrimaryAuthManager|AuthManagerDaemon|UtilDaemon)$
          windowrule=isfloating:1,isglobal:1,appid:^(zoom|Zoom)$
          windowrule=isfloating:1,title:^(Open File|Select a File|Save As|File Upload).*$
          windowrule=idleinhibit_when_focus:1,appid:^(steam_app_.*|gamescope)$
          # Steam/gamescope games may use VRR only while truly fullscreen.
          windowrule=vrr_only_fullscreen:1,appid:^(steam_app_.*|gamescope)$

          exec-once=${home}/.config/mango/autostart.sh
        '';
        validatedConfig = pkgs.runCommand "mango-config.conf" { } ''
          cp ${pkgs.writeText "mango-config.conf" configText} "$out"
          ${mango}/bin/mango -c "$out" -p
        '';
      in
      {
        home.packages = [ mangoScreenshot mango ];
        home.sessionVariables = {
          XDG_CURRENT_DESKTOP = "mango";
          NIXOS_OZONE_WL = "1";
          MOZ_ENABLE_WAYLAND = "1";
          GDK_BACKEND = "wayland,x11";
          QT_QPA_PLATFORM = "wayland;xcb";
          # Keep plain `nh os switch` on the Hyprland host by default.
          NH_OS_FLAKE = "${home}/Dotfiles/nixos-config#nixos";
        };
        # Fish does not always source Home Manager's session-vars file from an
        # already-generated config.fish, so export this default directly too.
        programs.fish.shellInit = ''
          set -gx NH_OS_FLAKE "${home}/Dotfiles/nixos-config#nixos"
        '';
        programs.serpantinum.systemd.environment = {
          XDG_CURRENT_DESKTOP = "mango";
          XDG_SESSION_DESKTOP = "mango";
        };

        home.pointerCursor = {
          enable = true;
          gtk.enable = true;
          x11.enable = true;
          package = arcMidnight;
          name = "ArcMidnight-Cursors";
          size = 24;
        };

        xdg.configFile."mango/config.conf".source = validatedConfig;
        xdg.configFile."mango/autostart.sh" = {
          source = mangoAutostart;
          executable = true;
        };

        systemd.user.targets.mango-session = {
          Unit = {
            Description = "MangoWM compositor session";
            Documentation = [ "man:systemd.special(7)" ];
            BindsTo = [ "graphical-session.target" ];
            Wants = [ "graphical-session-pre.target" ];
            After = [ "graphical-session-pre.target" ];
          };
        };

        systemd.user.services = {
          mango-idle = {
            Unit = {
              Description = "MangoWM idle and display power management";
              PartOf = [ "mango-session.target" ];
              After = [ "mango-session.target" ];
            };
            Service = {
              ExecStart = mangoIdle;
              Restart = "on-failure";
            };
            Install.WantedBy = [ "mango-session.target" ];
          };
          mango-polkit-agent = {
            Unit = {
              Description = "Polkit authentication agent for MangoWM";
              PartOf = [ "mango-session.target" ];
              After = [ "mango-session.target" ];
            };
            Service = {
              ExecStart = mangoPolkit;
              Restart = "on-failure";
            };
            Install.WantedBy = [ "mango-session.target" ];
          };
          ydotoold = {
            Unit = {
              Description = "ydotool input daemon";
              PartOf = [ "mango-session.target" ];
              After = [ "mango-session.target" ];
            };
            Service = {
              ExecStart = "${pkgs.ydotool}/bin/ydotoold";
              Restart = "on-failure";
            };
            Install.WantedBy = [ "mango-session.target" ];
          };
        };
      };
  };
}
