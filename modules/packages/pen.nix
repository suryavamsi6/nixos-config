# Pen (pen.dev, formerly pencil.dev) — Electron design tool.
#
# Upstream publishes Linux only as an AppImage and a tarball. The tarball is
# used here: it is the same Electron tree without the AppRun wrapper, so the
# bundled binary runs directly and no FUSE/appimageTools step is needed. It
# still needs /lib64/ld-linux-x86-64.so.2, hence buildFHSEnv like the other
# Electron desktops in this directory.
#
# The tarball ships no desktop entry and no icon; the icon is extracted from
# resources/app.asar (out/assets/1024x1024.png) at build time.
#
# chrome-sandbox stays mode 0755 and no --no-sandbox is passed: NixOS user
# namespaces supply the Chromium sandbox (same as claude-desktop.nix and
# pi-desktop.nix).
#
# pen does not update itself from the Nix store; app-update.yml is inert here.
# Bump version and hash together, or run `nix run .#update-pins`.
#
# The launcher is named pen-desktop to leave `pen` free for @pen.dev/cli,
# whose npm bin is also `pen`.
{ lib, ... }:
{
  options.flake.modules.homeManager.pen = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { config, pkgs, ... }:
      let
        version = "1.2.23";
        src = pkgs.fetchurl {
          url = "https://github.com/highagency/pen-desktop-releases/releases/download/v${version}/Pen-${version}-linux-x64.tar.gz";
          hash = "sha256-Yzjdo0vj7pZv+5rdHPQuA2DQdewrr5IN7f1kUhYRddI=";
        };
        contents = pkgs.runCommand "pen-${version}-contents" { } ''
          mkdir -p $out
          tar -xzf ${src} --strip-components=1 -C $out
          chmod 0755 $out/chrome-sandbox
        '';
        # `asar extract-file` unwraps the archive header, which is the only way
        # to reach the icon: nothing outside app.asar carries one.
        icon = pkgs.runCommand "pen-icon" { nativeBuildInputs = [ pkgs.asar ]; } ''
          mkdir -p $out/share/icons/hicolor/1024x1024/apps
          cd "$(mktemp -d)"
          asar extract-file ${contents}/resources/app.asar out/assets/1024x1024.png
          install -Dm644 1024x1024.png \
            $out/share/icons/hicolor/1024x1024/apps/pen-desktop.png
        '';
        # A real runner, not buildFHSEnv's default "bash": that makes /init
        # `exec bash "$@"` and bash refuses the ELF binary.
        penRun = pkgs.writeShellScript "pen-run" ''
          exec ${contents}/pen "$@"
        '';
        fhs = pkgs.buildFHSEnv (
          pkgs.appimageTools.defaultFhsEnvArgs
          // {
            name = "pen-fhs";
            runScript = "${penRun}";
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
        launcher = pkgs.writeShellScriptBin "pen-desktop" ''
          exec ${fhs}/bin/pen-fhs "$@"
        '';
        desktopItem = pkgs.makeDesktopItem {
          name = "pen-desktop";
          desktopName = "Pen";
          genericName = "Design tool";
          comment = "Design and build interfaces with an AI agent";
          exec = "${config.home.profileDirectory}/bin/pen-desktop %U";
          icon = "pen-desktop";
          categories = [
            "Graphics"
            "Development"
          ];
          startupNotify = true;
          # The Electron binary is named `pen`, so that is the WM_CLASS
          # Chromium derives when no --class is passed.
          startupWMClass = "pen";
        };
        app = pkgs.runCommand "pen-${version}" { } ''
          install -Dm755 ${launcher}/bin/pen-desktop $out/bin/pen-desktop
          install -Dm644 ${desktopItem}/share/applications/pen-desktop.desktop \
            $out/share/applications/pen-desktop.desktop
          install -Dm644 ${icon}/share/icons/hicolor/1024x1024/apps/pen-desktop.png \
            $out/share/icons/hicolor/1024x1024/apps/pen-desktop.png
        '';
      in
      {
        home.packages = [ app ];
      };
  };
}
