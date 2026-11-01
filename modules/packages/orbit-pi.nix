# Orbit Pi native workbench for the pi coding agent.
# Upstream Linux tarballs contain a standalone GPUI binary and desktop assets.
{ lib, ... }:
{
  options.flake.modules.homeManager.orbitPi = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { pkgs, ... }:
      let
        version = "0.2.13";
        src = pkgs.fetchurl {
          url = "https://github.com/imrj05/orbit/releases/download/v${version}/orbit-pi-${version}-x86_64-unknown-linux-gnu.tar.gz";
          hash = "sha256-bQmwKCNccKLbmVfrhMtOukAN9f/SZ5psK6Rwigp2kQA=";
        };
        orbitPi = pkgs.stdenvNoCC.mkDerivation {
          pname = "orbit-pi";
          inherit version src;
          sourceRoot = "orbit-pi-${version}-x86_64-unknown-linux-gnu";
          dontBuild = true;
          nativeBuildInputs = [ pkgs.autoPatchelfHook pkgs.makeWrapper ];
          buildInputs = with pkgs; [
            vulkan-loader
            stdenv.cc.cc.lib
            libxkbcommon
            libxcb
            libx11
          ];
          installPhase = ''
            runHook preInstall
            install -Dm755 bin/orbit-pi $out/libexec/orbit-pi
            mkdir -p $out/bin
            makeWrapper $out/libexec/orbit-pi $out/bin/orbit-pi \
              --prefix LD_LIBRARY_PATH : "${pkgs.vulkan-loader}/lib:${pkgs.lib.makeLibraryPath [ pkgs.stdenv.cc.cc.lib pkgs.libxkbcommon pkgs.libxcb pkgs.libx11 pkgs.wayland ]}"
            install -Dm644 share/applications/dev.orbit.pi.desktop \
              $out/share/applications/dev.orbit.pi.desktop
            install -Dm644 share/icons/hicolor/256x256/apps/dev.orbit.pi.png \
              $out/share/icons/hicolor/256x256/apps/dev.orbit.pi.png
            runHook postInstall
          '';
          meta = {
            description = "Native workbench for the pi coding agent";
            homepage = "https://orbitpi.app/";
            changelog = "https://github.com/imrj05/orbit/releases/tag/v${version}";
            license = lib.licenses.asl20;
            sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
            platforms = [ "x86_64-linux" ];
            mainProgram = "orbit-pi";
          };
        };
      in
      {
        home.packages = [ orbitPi ];
      };
  };
}
