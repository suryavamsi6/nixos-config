# Synara (trysynara.com) — local-first desktop command center that drives
# multiple coding-agent CLIs (Claude Code, Codex, OpenCode, Cursor, Pi, ...).
#
# Linux is published only as an AppImage. appimageTools extracts it at build
# time and the Electron binary runs inside buildFHSEnv for
# /lib64/ld-linux-x86-64.so.2, matching the other agent desktops here.
#
# Like openbot.nix, the AppRun is bypassed: it appends --no-sandbox when
# `unshare -Ur` fails, and Synara should keep the Chromium sandbox. The
# extracted tree also ships no desktop entry or hicolor icons, so this module
# creates both (the 1024x1024 icon is the AppImage's only one).
#
# Synara detects agent CLIs on PATH, so the launcher prepends the Home Manager
# profile — a desktop launch otherwise misses pi, claude, codex and friends.
#
# app-update.yml is inert from the Nix store; bump version and hash together
# or run `nix run .#update-pins`.
{ lib, ... }:
{
  options.flake.modules.homeManager.synara = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { config, pkgs, ... }:
      let
        version = "1.0.9";
        src = pkgs.fetchurl {
          url = "https://github.com/Emanuele-web04/synara/releases/download/v${version}/Synara-${version}-x86_64.AppImage";
          hash = "sha256-Rg+3c8xI99Vast9Emi5c/TZwYi3wQAiO/RmShnq3IO8=";
        };
        contents = pkgs.appimageTools.extract {
          pname = "synara";
          inherit version src;
        };
        # A real runner, not buildFHSEnv's default "bash": that makes /init
        # `exec bash "$@"` and bash refuses the ELF binary.
        synaraRun = pkgs.writeShellScript "synara-run" ''
          exec ${contents}/synara "$@"
        '';
        fhs = pkgs.buildFHSEnv (
          pkgs.appimageTools.defaultFhsEnvArgs
          // {
            name = "synara-fhs";
            runScript = "${synaraRun}";
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
        launcher = pkgs.writeShellScriptBin "synara" ''
          export PATH="${config.home.profileDirectory}/bin''${PATH:+:$PATH}"
          exec ${fhs}/bin/synara-fhs "$@"
        '';
        desktopItem = pkgs.makeDesktopItem {
          name = "synara";
          desktopName = "Synara";
          comment = "Local-first command center for parallel coding agents";
          exec = "${config.home.profileDirectory}/bin/synara %U";
          icon = "synara";
          categories = [
            "Development"
            "IDE"
          ];
          startupNotify = true;
          startupWMClass = "synara";
        };
        app = pkgs.runCommand "synara-${version}" { } ''
          install -Dm755 ${launcher}/bin/synara $out/bin/synara
          install -Dm644 ${desktopItem}/share/applications/synara.desktop \
            $out/share/applications/synara.desktop
          install -Dm644 ${contents}/usr/share/icons/hicolor/1024x1024/apps/synara.png \
            $out/share/icons/hicolor/1024x1024/apps/synara.png
        '';
      in
      {
        home.packages = [ app ];
      };
  };
}
