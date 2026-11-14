# Official ChatGPT desktop app for Linux, with Codex mode.
#
# OpenAI publishes a .deb for supported Linux distributions. NixOS is not on
# the supported list, so extract the official package and run its bundled
# Electron app in an FHS environment. The launcher is named Codex so it is
# easy to find with Super+Space; it opens the ChatGPT desktop app, where Codex
# is the coding workspace.
{ lib, ... }:
{
  options.flake.modules.homeManager.chatgptDesktop = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { pkgs, ... }:
      let
        version = "26.1111.21308";
        source = pkgs.fetchurl {
          # Official OpenAI download link. Keep the hash pinned; bump it with
          # the version after validating a new package release.
          url = "https://persistent.oaistatic.com/codex-app-prod/linux/deb/latest/chatgpt_amd64.deb";
          hash = "sha256-S0Q7xVc1ChsZO8LxuuIHyeo8n7XZT3yUpdPbqotVI1I=";
        };
        contents =
          pkgs.runCommand "chatgpt-desktop-deb-${version}"
            {
              nativeBuildInputs = [ pkgs.dpkg ];
            }
            ''
              actualVersion=$(dpkg-deb -f ${source} Version)
              if [ "$actualVersion" != "${version}" ]; then
                echo "ChatGPT package version $actualVersion does not match ${version}" >&2
                exit 1
              fi
              mkdir -p $out
              dpkg-deb -x ${source} $out
            '';
        chatgpt = pkgs.buildFHSEnv (
          pkgs.appimageTools.defaultFhsEnvArgs
          // {
            pname = "chatgpt";
            inherit version;
            runScript = "${contents}/usr/lib/chatgpt/ChatGPT";

            targetPkgs =
              p:
              pkgs.appimageTools.defaultFhsEnvArgs.targetPkgs p
              ++ [
                p.alsa-lib
                p.at-spi2-atk
                p.at-spi2-core
                p.atk
                p.cairo
                p.cups
                p.dbus
                p.expat
                p.glib
                p.gtk3
                p.libGL
                p.libnotify
                p.libsecret
                p.libudev-zero
                p.nss
                p.pango
                p.vulkan-loader
                p.xdg-utils
                p.libx11
                p.libxcomposite
                p.libxdamage
                p.libxext
                p.libxfixes
                p.libxrandr
                p.libxcb
                p.xz
              ];

            extraInstallCommands = ''
              install -Dm644 ${contents}/usr/share/applications/chatgpt.desktop \
                $out/share/applications/codex.desktop
              substituteInPlace $out/share/applications/codex.desktop \
                --replace-fail 'Name=ChatGPT' 'Name=Codex' \
                --replace-fail 'Comment=ChatGPT by OpenAI' 'Comment=OpenAI Codex desktop app' \
                --replace-fail 'Exec=chatgpt %U' "Exec=$out/bin/chatgpt %U" \
                --replace-fail 'Icon=chatgpt' "Icon=$out/share/pixmaps/chatgpt.png"
              install -Dm644 ${contents}/usr/share/pixmaps/chatgpt.png \
                $out/share/pixmaps/chatgpt.png
            '';

            meta = {
              description = "OpenAI ChatGPT desktop app with Codex mode";
              homepage = "https://openai.com/codex/";
              license = lib.licenses.unfree;
              sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
              platforms = [ "x86_64-linux" ];
              mainProgram = "chatgpt";
            };
          }
        );
      in
      {
        # Force our generated launcher over any entry left by a prior manual
        # install, so Super+Space always launches the Nix-managed app.
        xdg.dataFile."applications/codex.desktop" = {
          source = "${chatgpt}/share/applications/codex.desktop";
          force = true;
        };

        home.packages = [ chatgpt ];
      };
  };
}
