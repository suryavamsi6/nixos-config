# OpenBot desktop (openbot.run) from the upstream GitHub release AppImage.
#
# Upstream ships its own Nix packaging (nix/package.nix in nightly-labs/openbot)
# and this follows it. Two details are load-bearing:
#
#   * The AppImage's AppRun adds --no-sandbox when the system refuses an
#     unprivileged user namespace, and its desktop entry passes --no-sandbox
#     too. OpenBot must keep the Electron sandbox, so the FHS environment
#     starts the bundled Electron binary directly instead of AppRun.
#   * The AppImage bundles a Sunshine-based remote-desktop runtime built
#     against the Ubuntu libraries in upstream scripts/hosting/packages.txt.
#     This environment was not validated against them, so the directory is
#     dropped: OpenBot then reports remote desktop as unavailable rather than
#     failing at startup.
#
# OpenBot does not update itself from the Nix store (isNixStoreInstall in
# src/main/update-service.ts); Nix replaces the whole package instead. Bump
# version and hash together, or run `nix run .#update-pins`.
{
  lib,
  fetchurl,
  appimageTools,
  buildFHSEnv,
}:

let
  pname = "openbot";
  version = "0.49.0";

  src = fetchurl {
    url = "https://github.com/nightly-labs/openbot/releases/download/v0.49.0/OpenBot-0.49.0-x86_64.AppImage";
    hash = "sha256-R66/ITBdI/BRV3UTB8e4Jsu+sFl+dRgEKvW+b4QqV5s=";
  };

  contents = appimageTools.extract {
    inherit pname version src;
    postExtract = ''
      rm -rf $out/resources/remote-desktop-runtime
    '';
  };
in
buildFHSEnv (
  appimageTools.defaultFhsEnvArgs
  // {
    inherit pname version;

    # libsecret: Electron safeStorage, the one library upstream's .deb adds
    # beyond what the AppImage bundles.
    targetPkgs = pkgs: appimageTools.defaultFhsEnvArgs.targetPkgs pkgs ++ [ pkgs.libsecret ];

    runScript = "${contents}/openbot";

    extraInstallCommands = ''
      install -Dm444 ${contents}/openbot.desktop $out/share/applications/openbot.desktop
      substituteInPlace $out/share/applications/openbot.desktop \
        --replace-fail 'Exec=AppRun --no-sandbox %U' 'Exec=openbot %U'

      # The AppImage ships a single 1600x1600 icon, a size no icon theme
      # lists, so it goes in pixmaps instead of hicolor.
      install -Dm444 ${contents}/openbot.png $out/share/pixmaps/openbot.png
    '';

    meta = {
      description = "Local-first multi-agent desktop workspace for Codex, Claude, Grok and other coding agents";
      homepage = "https://github.com/nightly-labs/openbot";
      changelog = "https://github.com/nightly-labs/openbot/releases/tag/v${version}";
      license = {
        shortName = "polyform-nc-10";
        fullName = "PolyForm Noncommercial License 1.0.0";
        spdxId = "PolyForm-Noncommercial-1.0.0";
        url = "https://polyformproject.org/licenses/noncommercial/1.0.0/";
        free = false;
        redistributable = false;
      };
      sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
      platforms = [ "x86_64-linux" ];
      mainProgram = "openbot";
    };
  }
)
