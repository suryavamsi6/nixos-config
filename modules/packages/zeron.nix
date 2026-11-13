# Zeron's Linux release contains the desktop, its CLI and the engine sidecar.
# Keep the whole release together: the app locates the engine, UI and built-in
# plugins relative to its executable. Updates belong to the flake pin.
{ lib, ... }:
{
  options.flake.modules.homeManager.zeron = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { config, pkgs, ... }:
      let
        zeronVersion = "0.3.4";
        zeronSrc = pkgs.fetchurl {
          url = "https://github.com/zeronsh/zeron/releases/download/v${zeronVersion}/zeron-${zeronVersion}-linux-x86_64.tar.gz";
          hash = "sha256-60mMYIqfC0mbJg8LbbWJFUWNcuTKUaizCY/niJiz+VY=";
        };
        zeronContents = pkgs.runCommand "zeron-${zeronVersion}-contents" { } ''
          mkdir -p "$out"
          tar -xzf ${zeronSrc} --strip-components=1 -C "$out"
        '';
        zeronRun = pkgs.writeShellScript "zeron-run" ''
          export ZERON_AUTO_UPDATE=0
          if [ -z "''${SSH_AUTH_SOCK:-}" ] && [ -S "$HOME/.1password/agent.sock" ]; then
            export SSH_AUTH_SOCK="$HOME/.1password/agent.sock"
          fi
          exec ${zeronContents}/zeron "$@"
        '';
        zeronDesktopItem = pkgs.makeDesktopItem {
          name = "zeron";
          desktopName = "Zeron";
          genericName = "Coding Agent Controller";
          comment = "Control coding agents on this device";
          exec = "${config.home.profileDirectory}/bin/zeron %u";
          icon = "zeron";
          mimeTypes = [ "x-scheme-handler/zeron" ];
          categories = [
            "Development"
            "Utility"
          ];
          startupNotify = true;
          startupWMClass = "zeron";
        };
        zeron = pkgs.buildFHSEnv (
          pkgs.appimageTools.defaultFhsEnvArgs
          // {
            name = "zeron";
            runScript = "${zeronRun}";
            # The desktop starts a detached engine that keeps agent sessions
            # alive after the window or its launcher exits.
            dieWithParent = false;
            targetPkgs =
              p:
              pkgs.appimageTools.defaultFhsEnvArgs.targetPkgs p
              ++ [
                p.alsa-lib
                p.dbus
                p.systemd
                p.vulkan-loader
                p.libxkbcommon
                p.wayland
                p.libx11
                p.libxcb
                p.libxcursor
                p.libxi
                p.libxrandr
                # Release builds embed the browser helper but dynamically load
                # WebKitGTK 4.1 and JSON-GLib from the runtime environment.
                p.webkitgtk_4_1
                p.json-glib
              ];
            extraBwrapArgs = [
              "--share-net"
              ''--bind-try "$XDG_RUNTIME_DIR" "$XDG_RUNTIME_DIR"''
            ];
            extraInstallCommands = ''
              install -Dm644 ${zeronDesktopItem}/share/applications/zeron.desktop \
                "$out/share/applications/zeron.desktop"
              install -Dm644 ${zeronContents}/zeron.png \
                "$out/share/icons/hicolor/1024x1024/apps/zeron.png"
            '';
            meta = {
              description = "Desktop and CLI for managing coding agents";
              homepage = "https://zeron.sh";
              license = lib.licenses.mit;
              sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
              platforms = [ "x86_64-linux" ];
              mainProgram = "zeron";
            };
          }
        );
      in
      {
        # Override an entry left by an upstream per-user installation.
        xdg.dataFile."applications/zeron.desktop" = {
          source = "${zeronDesktopItem}/share/applications/zeron.desktop";
          force = true;
        };
        home.packages = [ zeron ];
      };
  };
}
