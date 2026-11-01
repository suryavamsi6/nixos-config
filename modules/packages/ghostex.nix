# Ghostex native agents workspace from the official Linux x64 AppImage.
# The release checksum is published on the upstream GitHub release page.
{ lib, ... }:
{
  options.flake.modules.homeManager.ghostex = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { pkgs, ... }:
      let
        version = "10.40.0";
        src = pkgs.fetchurl {
          url = "https://github.com/maddada/Ghostex/releases/download/v${version}/ghostex-${version}-linux-x64.AppImage";
          hash = "sha256-/wwZQOF/X9um76rrC2YpNORxObGm+SMoJdKFXsbtctY=";
        };
        contents = pkgs.appimageTools.extract {
          pname = "ghostex";
          inherit version src;
        };
        ghostex = pkgs.buildFHSEnv (
          pkgs.appimageTools.defaultFhsEnvArgs
          // {
            pname = "ghostex";
            inherit version;
            targetPkgs =
              p:
              pkgs.appimageTools.defaultFhsEnvArgs.targetPkgs p
              ++ [
                p.dbus
                p.libsecret
                p.libxkbcommon
                p.vulkan-loader
                p.wayland
                p.libx11
                p.libxcb
                p.libxcursor
                p.libxi
                p.libxrandr
              ];
            # AppRun's self-install path copies the bundle into
            # ~/.local/share/ghostex/appimage with upstream read-only modes.
            # On the next launch its cp --remove-destination cannot replace
            # those files, so launch the bundled app from the immutable store
            # directly. Its sibling server/runtime binaries stay alongside it.
            runScript = "${contents}/opt/ghostex/Ghostex";
            extraInstallCommands = ''
              install -Dm444 ${contents}/ghostex.desktop $out/share/applications/ghostex.desktop
              install -Dm444 ${contents}/ghostex.png $out/share/pixmaps/ghostex.png
            '';
            meta = {
              description = "Native all-in-one workspace for coding agents";
              homepage = "https://ghostex.dev/";
              changelog = "https://github.com/maddada/Ghostex/releases/tag/v${version}";
              license = lib.licenses.mit;
              sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
              platforms = [ "x86_64-linux" ];
              mainProgram = "ghostex";
            };
          }
        );
      in
      {
        home.packages = [ ghostex ];
      };
  };
}
