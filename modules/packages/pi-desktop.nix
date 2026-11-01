# Pi Desktop (pi-desktop.com) — Electron GUI frontend for the Pi coding agent.
#
# Upstream ships Linux only as an AppImage. appimageTools extracts it at build
# time, which keeps FUSE out of the runtime path; the Electron binary itself
# still needs /lib64/ld-linux-x86-64.so.2, so it runs inside buildFHSEnv like
# the other agent desktops here.
#
# The AppImage's AppRun adds --no-sandbox whenever `unshare -Ur` fails. Pi
# Desktop must keep the Chromium sandbox (same reasoning as openbot.nix), so
# the runScript execs the bundled binary directly instead of AppRun.
#
# Pi Desktop shells out to the `pi` CLI, so the launcher prepends the Home
# Manager profile to PATH; without it a desktop launch cannot resolve pi.
#
# Pi does not self-update from the Nix store (app-update.yml is unused here).
# Bump version and hash together, or run `nix run .#update-pins`.
{ lib, ... }:
{
  options.flake.modules.homeManager.piDesktop = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { config, pkgs, ... }:
      let
        version = "0.2.1-alpha";
        src = pkgs.fetchurl {
          url = "https://github.com/FaqFirebase/pi-desktop/releases/download/v${version}/Pi-Desktop-${version}-linux-x86_64.AppImage";
          hash = "sha256-QKngiMZ9JpthDSuPoGZ6Xv4M1Co87Nzmkm6aCfMjXn8=";
        };
        contents = pkgs.appimageTools.extract {
          pname = "pi-desktop";
          inherit version src;
        };
        # A real runner, not buildFHSEnv's default "bash": that makes /init
        # `exec bash "$@"` and bash refuses the ELF binary.
        piDesktopRun = pkgs.writeShellScript "pi-desktop-run" ''
          exec ${contents}/pi-desktop "$@"
        '';
        fhs = pkgs.buildFHSEnv (
          pkgs.appimageTools.defaultFhsEnvArgs
          // {
            name = "pi-desktop-fhs";
            runScript = "${piDesktopRun}";
            targetPkgs =
              p:
              pkgs.appimageTools.defaultFhsEnvArgs.targetPkgs p
              ++ (with p; [
                libsecret
                xdg-utils
                desktop-file-utils
              ]);
          }
        );
        launcher = pkgs.writeShellScriptBin "pi-desktop" ''
          export PATH="${config.home.profileDirectory}/bin''${PATH:+:$PATH}"
          exec ${fhs}/bin/pi-desktop-fhs "$@"
        '';
        desktopItem = pkgs.makeDesktopItem {
          name = "pi-desktop";
          desktopName = "Pi Desktop";
          comment = "Desktop GUI for the Pi coding agent";
          exec = "${config.home.profileDirectory}/bin/pi-desktop %U";
          icon = "pi-desktop";
          categories = [ "Development" ];
          startupNotify = true;
          startupWMClass = "pi-desktop";
        };
        app = pkgs.runCommand "pi-desktop-${version}" { } ''
          install -Dm755 ${launcher}/bin/pi-desktop $out/bin/pi-desktop
          install -Dm644 ${desktopItem}/share/applications/pi-desktop.desktop \
            $out/share/applications/pi-desktop.desktop
          for size in 16x16 32x32 64x64 128x128 256x256 512x512; do
            install -Dm644 ${contents}/usr/share/icons/hicolor/$size/apps/pi-desktop.png \
              $out/share/icons/hicolor/$size/apps/pi-desktop.png
          done
        '';
      in
      {
        home.packages = [ app ];
      };
  };
}
