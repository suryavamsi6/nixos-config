# Hokum Wayland notification daemon for the Hyprland desktop.
{ lib, ... }:
{
  options.flake.modules.homeManager.hokum = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { pkgs, ... }:
      let
        hokumVersion = "0.1.2";
        hokumBinary = pkgs.fetchurl {
          url = "https://github.com/anomalyco/hokum/releases/download/v${hokumVersion}/hokum-${hokumVersion}-linux-x64";
          hash = "sha256-752TL2ZG1MdKXsOCq5dFhfDHm/wjMh3AfDpEDK6sKyU=";
          executable = true;
        };
        hokum = pkgs.stdenvNoCC.mkDerivation {
          pname = "hokum";
          version = hokumVersion;
          src = hokumBinary;
          dontUnpack = true;

          installPhase = ''
            runHook preInstall
            install -Dm755 $src $out/bin/hokum
            runHook postInstall
          '';

          meta = {
            description = "Freedesktop notification daemon for Wayland";
            homepage = "https://hokum.app";
            license = lib.licenses.mit;
            sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
            platforms = [ "x86_64-linux" ];
            mainProgram = "hokum";
          };
        };
      in
      {
        home.packages = [ hokum ];

        # Hokum's upstream service activates on org.freedesktop.Notifications.
        # Bind its executable to the profile path and conflict with legacy daemons.
        systemd.user.services.hokum = {
          Unit = {
            Description = "Hokum Wayland notification daemon";
            Documentation = "https://hokum.app";
            PartOf = [ "graphical-session.target" ];
            After = [ "graphical-session.target" ];
            Conflicts = [ "mako.service" "dunst.service" "swaync.service" ];
          };
          Service = {
            Type = "dbus";
            BusName = "org.freedesktop.Notifications";
            ExecCondition = "${pkgs.bash}/bin/bash -c 'test -n \"$WAYLAND_DISPLAY\"'";
            ExecStart = "${hokum}/bin/hokum service";
            Restart = "on-failure";
            RestartSec = 2;
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };

        xdg.dataFile."dbus-1/services/org.freedesktop.Notifications.service".text = ''
          [D-BUS Service]
          Name=org.freedesktop.Notifications
          Exec=${hokum}/bin/hokum service
          SystemdService=hokum.service
        '';

        xdg.dataFile."applications/hokum.desktop".text = ''
          [Desktop Entry]
          Type=Application
          Name=Hokum
          GenericName=Notification Settings
          Comment=Style and configure your notifications
          Exec=${hokum}/bin/hokum
          Icon=preferences-desktop-notification
          Terminal=false
          StartupNotify=true
          Categories=Settings;DesktopSettings;
          Keywords=notifications;notification;daemon;do not disturb;
        '';
      };
  };
}
