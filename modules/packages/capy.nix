# Capy (capy.ai) desktop. Linux publishes an AppImage (self-updating), a .deb,
# and a .tar.gz meant for packagers. This uses the tarball: with APPIMAGE unset
# and no resources/package-type file, Capy treats the install as unmanaged and
# Check for Updates says the package delivers the next version.
#
# The electron binary's interpreter is /lib64/ld-linux-x86-64.so.2, so it runs
# in a buildFHSEnv, like the other agent desktops. On Linux the app registers
# capy:// by symlink'ing ~/.local/share/capy/protocols/capy at
# `process.env.APPIMAGE || process.execPath` and pointing a desktop file at
# that symlink. execPath is the raw binary, which cannot start outside the
# chroot. A same-length edit in app.asar renames that one read to CAPY_BIN
# (eight characters, matching APPIMAGE — a longer name shifts asar offsets).
# The launcher exports CAPY_BIN as its own path, so the symlink targets the
# wrapper. Do not set APPIMAGE: that turns the self-updater on. Do not revert
# the asar string. Asar integrity is off in 0.4.7 (fuse
# EnableEmbeddedAsarIntegrityValidation is 0). Bump capyVersion and the
# fetchurl hash together; the unpack step fails if the string is no longer
# unique or the patch changes the file size.
{ lib, ... }:
{
  options.flake.modules.homeManager.capy = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { config, pkgs, ... }:
      let
        capyVersion = "0.4.7";
        capySrc = pkgs.fetchurl {
          url = "https://downloads.capy.ai/stable/capy-${capyVersion}-x64.tar.gz";
          hash = "sha256-o3lvI8Z2NDBHiqZb1HqJFDw8dpJt7AF8jydIczcaWJ0=";
        };
        capyUnpacked =
          pkgs.runCommand "capy-${capyVersion}-unpacked"
            {
              nativeBuildInputs = [ pkgs.perl ];
            }
            ''
              mkdir unpacked
              tar -xzf ${capySrc} -C unpacked --strip-components=1
              asar=unpacked/resources/app.asar
              before=$(stat -c %s "$asar")
              hits=$(perl -ne 'BEGIN { $c = 0 } $c++ while /process\.env\.APPIMAGE \|\| process\.execPath/g; END { print $c }' "$asar")
              test "$hits" = 1
              perl -pi -e 's/process\.env\.APPIMAGE \|\| process\.execPath/process.env.CAPY_BIN || process.execPath/' "$asar"
              after=$(stat -c %s "$asar")
              test "$before" = "$after"
              hits=$(perl -ne 'BEGIN { $c = 0 } $c++ while /process\.env\.CAPY_BIN \|\| process\.execPath/g; END { print $c }' "$asar")
              test "$hits" = 1
              chmod 755 unpacked/capy
              mv unpacked $out
            '';
        # A real runner, not buildFHSEnv's default "bash": that makes /init
        # `exec bash "$@"` and bash refuses the ELF.
        capyRun = pkgs.writeShellScript "capy-run" ''
          exec ${capyUnpacked}/capy --no-sandbox "$@"
        '';
        capyFhs = pkgs.buildFHSEnv (
          pkgs.appimageTools.defaultFhsEnvArgs
          // {
            name = "capy-fhs";
            runScript = "${capyRun}";
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
        capyLauncher = pkgs.writeShellScriptBin "capy" ''
          # Realpath of this script. Capy symlinks its capy:// handler at it.
          export CAPY_BIN="$(${pkgs.coreutils}/bin/readlink -f "''${BASH_SOURCE[0]}")"
          # Desktop launches have no agent socket. Match hermes-desktop.
          if [ -z "''${SSH_AUTH_SOCK:-}" ] && [ -S "$HOME/.1password/agent.sock" ]; then
            export SSH_AUTH_SOCK="$HOME/.1password/agent.sock"
          fi
          exec ${capyFhs}/bin/capy-fhs "$@"
        '';
        capyDesktopItem = pkgs.makeDesktopItem {
          name = "capy";
          desktopName = "Capy";
          comment = "Coding agent for local folders and cloud machines";
          exec = "${config.home.profileDirectory}/bin/capy %U";
          icon = "capy";
          mimeTypes = [ "x-scheme-handler/capy" ];
          categories = [ "Development" ];
          startupNotify = true;
          startupWMClass = "capy";
        };
        capy =
          pkgs.runCommand "capy-${capyVersion}"
            {
              meta = {
                description = "Capy desktop coding agent";
                homepage = "https://capy.ai/";
                platforms = [ "x86_64-linux" ];
              };
            }
            ''
              mkdir -p $out/bin $out/share/applications $out/share/icons/hicolor/512x512/apps
              ln -s ${capyLauncher}/bin/capy $out/bin/capy
              install -Dm644 ${capyDesktopItem}/share/applications/capy.desktop \
                $out/share/applications/capy.desktop
              install -Dm644 ${capyUnpacked}/resources/icon.png \
                $out/share/icons/hicolor/512x512/apps/capy.png
            '';
      in
      {
        home.packages = [ capy ];
      };
  };
}
