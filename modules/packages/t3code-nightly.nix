# T3 Code nightly (pingdotgg/t3code), replacing nixpkgs' stable `t3code`.
#
# Upstream publishes two build products per nightly tag, and the flake uses
# both:
#   * the desktop app as an electron-builder .deb (no FHS-free way to run it:
#     its Electron binary wants /lib64/ld-linux-x86-64.so.2 and glib, so it
#     runs inside a buildFHSEnv, like grok-bot above in dev.nix);
#   * the standalone `t3` CLI/server tarball (Bun-compiled native binary plus
#     the web client and the Rust resource monitor), which autoPatchelf can
#     make self-contained.
#
# Nix owns updates, so the upstream in-app updater and `t3 update` are not
# used; bump t3codeNightlyVersion and refresh both hashes together.
{ lib, ... }:
{
  options.flake.modules.homeManager.t3codeNightly = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { pkgs, config, ... }:
      let
        t3codeNightlyVersion = "0.1.6-nightly.20261029.3892";
        # Both artifacts come from the same GitHub release tag.
        t3codeNightlyBaseUrl = "https://github.com/pingdotgg/t3code/releases/download/v${t3codeNightlyVersion}";

        # Upstream desktop app name is "T3 Code (Nightly)" and the deb installs
        # under /opt, matching what electron-builder ships for other distros.
        t3codeAppDir = "T3 Code (Nightly)";

        t3codeNightlyDeb = pkgs.fetchurl {
          name = "T3-Code-${t3codeNightlyVersion}-amd64.deb";
          url = "${t3codeNightlyBaseUrl}/T3-Code-${t3codeNightlyVersion}-amd64.deb";
          hash = "sha256-d95pjEO/g7UAny0Qtk97lQRmUs3d82ZaBhaDqCjez10=";
        };
        t3codeNightlyUnpacked = pkgs.runCommand "t3code-nightly-${t3codeNightlyVersion}-unpacked" { } ''
          ${pkgs.dpkg}/bin/dpkg-deb -x ${t3codeNightlyDeb} $out
        '';

        t3codeNightlyDesktopItem = pkgs.makeDesktopItem {
          name = "t3code-nightly";
          desktopName = "T3 Code (Nightly)";
          comment = "T3 Code desktop app for coding agents (nightly)";
          exec = "${config.home.profileDirectory}/bin/t3code-nightly %U";
          icon = "t3code";
          # Upstream registers the t3code:// and t3code-dev:// deep links.
          mimeTypes = [
            "x-scheme-handler/t3code"
            "x-scheme-handler/t3code-dev"
          ];
          categories = [ "Development" ];
          startupNotify = true;
          startupWMClass = "t3code";
        };

        # NixOS' chrome-sandbox is not setuid-root, so pass --no-sandbox the
        # way the other Electron packages here do.
        t3codeNightlyDesktop = pkgs.buildFHSEnv (
          pkgs.appimageTools.defaultFhsEnvArgs
          // {
            name = "t3code-nightly";
            runScript = "${pkgs.writeShellScript "t3code-nightly-run" ''
              exec "${t3codeNightlyUnpacked}/opt/${t3codeAppDir}/t3code" --no-sandbox "$@"
            ''}";
            targetPkgs =
              p:
              pkgs.appimageTools.defaultFhsEnvArgs.targetPkgs p
              ++ (with p; [
                libsecret
                xdg-utils
              ]);
            extraInstallCommands = ''
              install -Dm644 ${t3codeNightlyDesktopItem}/share/applications/t3code-nightly.desktop \
                $out/share/applications/t3code-nightly.desktop
              # The deb ships a full hicolor icon set; the app entry's Icon=
              # name is upstream's `t3code`.
              ${pkgs.coreutils}/bin/mkdir -p $out/share/icons
              ${pkgs.coreutils}/bin/cp -r --no-preserve=mode \
                ${t3codeNightlyUnpacked}/usr/share/icons/hicolor $out/share/icons/hicolor
            '';
            meta = {
              description = "T3 Code desktop app for coding agents (nightly)";
              homepage = "https://t3.codes";
              license = lib.licenses.mit;
              sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
              platforms = [ "x86_64-linux" ];
              mainProgram = "t3code-nightly";
            };
          }
        );

        # The CLI/server tarball is a Bun-compiled binary that ships its own
        # client assets and resource-monitor next to it; only the glibc libs
        # need repointing. Keep the tree intact (the binary resolves client/
        # relative to itself), so patchelf in place rather than splitting.
        t3codeNightlyCliSrc = pkgs.fetchurl {
          name = "t3-${t3codeNightlyVersion}-linux-x64.tar.gz";
          url = "${t3codeNightlyBaseUrl}/t3-${t3codeNightlyVersion}-linux-x64.tar.gz";
          hash = "sha256-Zhd8RNDWXh8bo8uKAF5lljD0EsB09bWoU8UZOCRiD0A=";
        };
        t3codeNightlyCli = pkgs.stdenv.mkDerivation {
          pname = "t3code-nightly-cli";
          version = t3codeNightlyVersion;
          src = t3codeNightlyCliSrc;
          nativeBuildInputs = [
            pkgs.autoPatchelfHook
            pkgs.makeWrapper
          ];
          buildInputs = [
            pkgs.stdenv.cc.cc.lib
            pkgs.zlib
          ];
          # The tarball already carries prebuilt binaries and assets.
          dontBuild = true;
          # `t3` is a single-file Node SEA/Bun bundle: the runtime image is
          # appended to the ELF, so stripping deletes the payload and the
          # binary dies with "Assertion failed: (magic) == (kMagic)".
          dontStrip = true;
          # A single top-level directory holding bin, client/ and resource-monitor/.
          sourceRoot = "t3-${t3codeNightlyVersion}-linux-x64";
          installPhase = ''
            runHook preInstall
            mkdir -p $out/libexec/t3code
            cp -r . $out/libexec/t3code/
            mkdir -p $out/bin
            makeWrapper $out/libexec/t3code/t3 $out/bin/t3 \
              --prefix PATH : ${lib.makeBinPath [ pkgs.git pkgs.gh ]}
            runHook postInstall
          '';
          meta = {
            description = "T3 Code CLI and server (nightly)";
            homepage = "https://t3.codes";
            license = lib.licenses.mit;
            sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
            platforms = [ "x86_64-linux" ];
            mainProgram = "t3";
          };
        };
      in
      {
        home.packages = [
          t3codeNightlyDesktop
          t3codeNightlyCli
        ];
      };
  };
}
