# DSH Desktop NEXT from the official x64 Linux AppImage release.
{ lib, ... }:
{
  options.flake.modules.homeManager.dshDesktopNext = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { config, pkgs, ... }:
      let
        version = "2.0.20-next";
        src = pkgs.fetchurl {
          url = "https://github.com/anywhere-labs/dsh-desktop/releases/download/v${version}/DSH-NEXT-${version}-x86_64.AppImage";
          hash = "sha256-YfJLVvVVX2Pd/dP5XO3bGdLdA16/PaDHfb8dBxa0Ceg=";
        };
        contents = pkgs.appimageTools.extract {
          pname = "dsh-desktop-next";
          inherit version src;
        };
        fhs = pkgs.buildFHSEnv (
          pkgs.appimageTools.defaultFhsEnvArgs
          // {
            name = "dsh-desktop-next-fhs";
            runScript = "appimage-exec.sh -w ${contents} --";
            targetPkgs =
              p:
              [ pkgs.appimageTools.appimage-exec ]
              ++ pkgs.appimageTools.defaultFhsEnvArgs.targetPkgs p
              ++ [
                p.libsecret
                p.bubblewrap
              ];
          }
        );
        launcher = pkgs.writeShellScriptBin "dsh-desktop-next" ''
          export PATH="${config.home.profileDirectory}/bin:${pkgs.bubblewrap}/bin''${PATH:+:$PATH}"
          exec ${fhs}/bin/dsh-desktop-next-fhs "$@"
        '';
        desktopItem = pkgs.makeDesktopItem {
          name = "dsh-desktop-next";
          desktopName = "DSH Desktop NEXT";
          comment = "Experimental DeepSeek Harness desktop workspace";
          exec = "${launcher}/bin/dsh-desktop-next %U";
          icon = "applications-development";
          categories = [ "Development" ];
          startupNotify = true;
        };
        app = pkgs.runCommand "dsh-desktop-next-${version}" { } ''
          install -Dm755 ${launcher}/bin/dsh-desktop-next $out/bin/dsh-desktop-next
          install -Dm644 ${desktopItem}/share/applications/dsh-desktop-next.desktop \
            $out/share/applications/dsh-desktop-next.desktop
        '';
      in
      {
        home.packages = [ app ];
      };
  };
}
