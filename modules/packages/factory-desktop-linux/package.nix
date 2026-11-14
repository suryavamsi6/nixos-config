# Factory Desktop (droid/factory.app) unofficial Linux port, 1.1.0.
#
# Built locally from the authorized official macOS DMG by the
# ~/Projects/factory-desktop-linux port project
# (`make build-app deb VERSION=1.1.0` there), which swaps in the Linux
# Electron runtime, patches the asar (websocket daemon transport, window
# controls, native updater bridge, ...), and packages a .deb.
# Do not redistribute.
#
# The deb is not in the repository: it is added to the store with
#   nix-store --add-fixed sha256 ~/Projects/factory-desktop-linux/dist/factory-desktop_1.1.0_amd64.deb
# and pinned here by its SRI hash. requireFile is pure, so the flake still
# evaluates with --pure; it just refuses to build until the deb is present.
#
# Absolute-path contract from the patcher, handled inside the FHS env:
#   /usr/lib/factory-desktop/update-bridge.cjs (required by the patched bundle)
{ pkgs }:

let
  version = "1.1.0";
  deb = pkgs.requireFile {
    name = "factory-desktop_${version}_amd64.deb";
    hash = "sha256-+OewfBMTEqUDBu1gRHXMGnc39kxK4FfTdyaRp98bMG0=";
    message = "Build the Factory Desktop deb locally and add it with nix-store --add-fixed sha256 /path/to/factory-desktop_${version}_amd64.deb";
  };

  contents =
    pkgs.runCommand "factory-desktop-deb-${version}"
      {
        nativeBuildInputs = [ pkgs.dpkg ];
      }
      ''
        mkdir -p $out
        dpkg-deb -x ${deb} $out
      '';

  # Match the desktop release and supply the CLI explicitly to its daemon.
  droid = pkgs.stdenv.mkDerivation {
    pname = "factory-droid";
    inherit version;
    src = pkgs.fetchurl {
      url = "https://downloads.factory.ai/factory-cli/releases/${version}/linux/x64/droid";
      hash = "sha256-kEha+c3gy0wUSkxUZJkq0dMAT1GSnGDC4NM7q6R2Stg=";
    };
    dontUnpack = true;
    # Droid is a Bun executable with an appended payload; patchelf breaks it.
    dontFixup = true;
    installPhase = ''
      install -Dm755 "$src" "$out/bin/droid"
    '';
  };

  factoryRoot = "${contents}/opt/Factory";

  # The deb launcher already exports FACTORY_DISABLE_KEYRING=1,
  # FACTORY_APP_ROOT, CHROME_DESKTOP and BAMF_DESKTOP_FILE_HINT.
  #
  # The desktop gets its own Factory home and Chromium profile so it never
  # shares ~/.factory with the standalone droid CLI. This mirrors what the
  # ash-eriga port does in runtime/launch.sh; without it, desktop and CLI
  # sessions, credentials and daemon state collide.
  dataDir = "\${XDG_DATA_HOME:-$HOME/.local/share}/factory-desktop";

  factoryRun = pkgs.writeShellScript "factory-desktop-run" ''
    export FACTORY_DROID_PATH="''${FACTORY_DROID_PATH:-${droid}/bin/droid}"
    factory_data="${dataDir}"
    if mkdir -p "$factory_data/factory-home" "$factory_data/user-data" 2>/dev/null; then
      chmod 700 "$factory_data" 2>/dev/null || true
      export FACTORY_HOME_OVERRIDE="$factory_data/factory-home"
      set -- "--user-data-dir=$factory_data/user-data" "$@"
    fi
    exec ${factoryRoot}/factory-desktop-launcher "$@"
  '';

  fhs = pkgs.buildFHSEnv (
    pkgs.appimageTools.defaultFhsEnvArgs
    // {
      name = "factory-desktop-fhs";
      runScript = "${factoryRun}";

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

      extraBuildCommands = ''
        # The patched bundle requires the update bridge at
        # /usr/lib/factory-desktop/update-bridge.cjs. The FHS rootfs has
        # usr/lib -> usr/lib64 (usrmerge), so stage it under lib64 and the
        # absolute path resolves inside the sandbox.
        mkdir -p $out/usr/lib64/factory-desktop
        ln -sfn ${contents}/usr/lib/factory-desktop/update-bridge.cjs \
          $out/usr/lib64/factory-desktop/update-bridge.cjs

        # The bridge hardcodes HELPER = "/usr/bin/factory-update-manager"
        # (update-bridge.cjs:6) and probes it with fs.existsSync before any
        # spawn. The FHS rootfs ships a /usr/bin but not this binary, so
        # every update check reported "Factory update manager is
        # unavailable" and the window showed a Retry button. Stage it at the
        # exact absolute path the bridge expects.
        mkdir -p $out/usr/bin
        ln -sfn ${contents}/usr/bin/factory-update-manager \
          $out/usr/bin/factory-update-manager
      '';
    }
  );

  launcher = pkgs.writeShellScriptBin "factory-desktop" ''
    exec ${fhs}/bin/factory-desktop-fhs "$@"
  '';

  desktopItem = pkgs.makeDesktopItem {
    name = "factory-desktop";
    desktopName = "Factory Desktop";
    comment = "Factory Desktop (unofficial Linux port)";
    exec = "${launcher}/bin/factory-desktop %U";
    icon = "factory-desktop";
    categories = [
      "Development"
      "IDE"
    ];
    startupNotify = true;
    startupWMClass = "factory";
    mimeTypes = [ "x-scheme-handler/factory-desktop" ];
  };

  app =
    pkgs.runCommand "factory-desktop-${version}"
      {
        passthru = {
          inherit contents fhs;
          update-manager = "${contents}/usr/bin/factory-update-manager";
        };
      }
      ''
        install -Dm755 ${launcher}/bin/factory-desktop $out/bin/factory-desktop
        install -Dm644 ${desktopItem}/share/applications/factory-desktop.desktop \
          $out/share/applications/factory-desktop.desktop
        install -Dm644 ${contents}/usr/share/icons/hicolor/512x512/apps/factory-desktop.png \
          $out/share/icons/hicolor/512x512/apps/factory-desktop.png
      '';
in
app
