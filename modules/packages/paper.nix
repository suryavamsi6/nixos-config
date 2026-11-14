# Paper (paper.design) — connected design canvas, from upstream's Linux .deb.
#
# Upstream ships AppImage, .deb and .rpm for x64 and arm64. The .deb is used
# here: it is a plain Electron tree under /opt/Paper, so unpacking it with
# dpkg-deb avoids the AppImage's FUSE layer. The binary still needs
# /lib64/ld-linux-x86-64.so.2, hence buildFHSEnv like the other Electron
# desktops in this directory.
#
# Upstream's own desktop entry wraps the binary in `/bin/sh -c` and appends
# --no-sandbox unless `unshare -Ur` succeeds. Like pi-desktop.nix and
# synara.nix this bypasses that wrapper and execs the binary directly with no
# --no-sandbox, keeping the Chromium sandbox (NixOS user namespaces supply it;
# chrome-sandbox itself is not setuid-root, so it stays mode 0755).
#
# Paper's bundled MCP server is registered through the app UI, not here.
#
# Paper does not update itself from the Nix store. Bump version and hash
# together, or run `nix run .#update-pins`.
{ lib, ... }:
{
  options.flake.modules.homeManager.paper = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { config, pkgs, ... }:
      let
        version = "0.5.19";
        src = pkgs.fetchurl {
          url = "https://download.paper.design/linux/deb/x64";
          hash = "sha256-HJtG+WAh8zm2tV4GjWjXJvIT7aw9Lb3IP8gU34u7MH8=";
        };
        # The download URL is unversioned, so the version above only labels the
        # derivation; the hash is what actually pins this build.
        contents = pkgs.runCommand "paper-desktop-${version}-contents" {
          nativeBuildInputs = [ pkgs.dpkg ];
        } ''
          mkdir -p $out
          dpkg-deb --fsys-tarfile ${src} \
            | tar --no-same-owner --no-same-permissions -xf - -C $out
          chmod -R u+w $out
          chmod 0755 $out/opt/Paper/chrome-sandbox
        '';
        # A real runner, not buildFHSEnv's default "bash": that makes /init
        # `exec bash "$@"` and bash refuses the ELF binary.
        paperRun = pkgs.writeShellScript "paper-run" ''
          exec ${contents}/opt/Paper/paper-desktop "$@"
        '';
        fhs = pkgs.buildFHSEnv (
          pkgs.appimageTools.defaultFhsEnvArgs
          // {
            name = "paper-fhs";
            runScript = "${paperRun}";
            targetPkgs =
              p:
              pkgs.appimageTools.defaultFhsEnvArgs.targetPkgs p
              ++ (with p; [
                libsecret
                libnotify
                xdg-utils
                desktop-file-utils
              ]);
          }
        );
        launcher = pkgs.writeShellScriptBin "paper-desktop" ''
          exec ${fhs}/bin/paper-fhs "$@"
        '';
        desktopItem = pkgs.makeDesktopItem {
          name = "paper-desktop";
          desktopName = "Paper";
          genericName = "Design tool";
          comment = "Connected design canvas for teams and agents";
          exec = "${config.home.profileDirectory}/bin/paper-desktop %U";
          icon = "paper-desktop";
          categories = [ "Graphics" "Development" ];
          # Both paper:// and paper-dev:// are registered by the .deb.
          mimeTypes = [
            "x-scheme-handler/paper"
            "x-scheme-handler/paper-dev"
          ];
          startupNotify = true;
          # The .deb claims StartupWMClass=Paper, but the binary presents
          # WM_CLASS `paper-desktop` on Wayland (measured with hyprctl).
          startupWMClass = "paper-desktop";
        };
        app = pkgs.runCommand "paper-desktop-${version}" { } ''
          install -Dm755 ${launcher}/bin/paper-desktop $out/bin/paper-desktop
          install -Dm644 ${desktopItem}/share/applications/paper-desktop.desktop \
            $out/share/applications/paper-desktop.desktop
          # The .deb ships a complete hicolor set for paper-desktop.
          mkdir -p $out/share/icons
          cp -r --no-preserve=mode ${contents}/usr/share/icons/hicolor $out/share/icons/hicolor
        '';
      in
      {
        home.packages = [ app ];
      };
  };
}
