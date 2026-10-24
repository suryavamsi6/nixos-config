# Claude Code Router (github:musistudio/claude-code-router) — local model
# gateway and desktop control plane for Claude Code, Codex, Grok, and the
# other agents it profiles.
#
# Linux ships an Electron AppImage. The binary's interpreter is
# /lib64/ld-linux-x86-64.so.2, so it runs in a buildFHSEnv, like the other
# agent desktops. The runner execs that ELF directly and leaves APPIMAGE
# unset: AppRun would point the variable at the store path, and
# electron-updater would try to replace it. Updates stay with this pin.
# Upstream's desktop entry always passes --no-sandbox. Bump ccrVersion and
# the fetchurl hash together.
{ lib, ... }:
{
  options.flake.modules.homeManager.claudeCodeRouter = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { config, pkgs, ... }:
      let
        ccrVersion = "3.1.3";
        ccrSrc = pkgs.fetchurl {
          url = "https://github.com/musistudio/claude-code-router/releases/download/v${ccrVersion}/Claude-Code-Router_${ccrVersion}.AppImage";
          hash = "sha256-+KCJIF5dBq+W5/q0qJxhxDP9SlZzT5Abr9FavJuFLOo=";
        };
        ccrContents = pkgs.appimageTools.extract {
          pname = "claude-code-router";
          version = ccrVersion;
          src = ccrSrc;
        };
        # A real runner, not buildFHSEnv's default "bash": that makes /init
        # `exec bash "$@"` and bash refuses the ELF.
        ccrRun = pkgs.writeShellScript "claude-code-router-run" ''
          unset APPIMAGE
          contents=${ccrContents}
          export PATH="$contents:$contents/usr/sbin''${PATH:+:$PATH}"
          export XDG_DATA_DIRS="$contents/usr/share''${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}"
          export LD_LIBRARY_PATH="$contents/usr/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
          exec "$contents/claude-code-router" --no-sandbox "$@"
        '';
        ccrDesktopItem = pkgs.makeDesktopItem {
          name = "claude-code-router";
          desktopName = "Claude Code Router";
          comment = "Local model gateway and control plane for coding agents";
          exec = "${config.home.profileDirectory}/bin/claude-code-router %U";
          icon = "claude-code-router";
          mimeTypes = [ "x-scheme-handler/ccr" ];
          categories = [
            "Development"
            "Utility"
          ];
          startupNotify = true;
          startupWMClass = "Claude Code Router";
        };
        ccr = pkgs.buildFHSEnv (
          pkgs.appimageTools.defaultFhsEnvArgs
          // {
            name = "claude-code-router";
            runScript = "${ccrRun}";
            targetPkgs =
              p:
              pkgs.appimageTools.defaultFhsEnvArgs.targetPkgs p
              ++ [
                p.libsecret
              ];
            extraInstallCommands = ''
              install -Dm644 ${ccrDesktopItem}/share/applications/claude-code-router.desktop \
                $out/share/applications/claude-code-router.desktop
              for size in 16x16 24x24 32x32 48x48 64x64 128x128 256x256 512x512; do
                install -Dm644 ${ccrContents}/usr/share/icons/hicolor/$size/apps/claude-code-router.png \
                  $out/share/icons/hicolor/$size/apps/claude-code-router.png
              done
            '';
            meta = {
              description = "Local model gateway and control plane for coding agents";
              homepage = "https://github.com/musistudio/claude-code-router";
              license = lib.licenses.mit;
              platforms = [ "x86_64-linux" ];
              mainProgram = "claude-code-router";
            };
          }
        );
      in
      {
        # An AppImage run writes this entry under XDG_DATA_HOME, which is
        # searched before the profile and would keep a store Exec. force
        # replaces that file instead of aborting activation.
        xdg.dataFile."applications/claude-code-router.desktop" = {
          source = "${ccrDesktopItem}/share/applications/claude-code-router.desktop";
          force = true;
        };

        home.packages = [ ccr ];
      };
  };
}
