# Hermes Desktop (hermes-agent.nousresearch.com) — Nous Research's Electron
# shell for the Hermes agent.
#
# Linux has no prebuilt download: the official installer clones the agent
# checkout into ~/.hermes/hermes-agent, stages its uv/Python/Node toolchain,
# and builds the desktop app into apps/desktop/release. On Linux upstream
# packages with electron-builder --dir, so the artifact is the unpacked
# directory app (release/linux-unpacked/{h,H}ermes), not an AppImage. The
# module follows the ComfyUI-style split — wrappers manage the upstream
# install/build in user state, and the launcher runs the built binary
# through an FHS env (Electron needs /lib64/ld-linux-x86-64.so.2 plus
# GTK/NSS, none of which NixOS exposes); an AppImage is preferred if one
# ever appears (APPIMAGE then exported for electron-updater). The runScript
# is a real runner script, NOT the buildFHSEnv default "bash": with the
# default, the generated /init does `exec bash "$@"`, which bash-interprets
# the command as a shell script and dies on ELF binaries with
# "cannot execute binary file". The #nixos host needs programs.nix-ld for
# the bootstrap toolchain (see nixos-hyprland.nix).
{ lib, ... }:
{
  options.flake.modules.homeManager.hermesDesktop = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { pkgs, ... }:
      let
        # Pinned official installer. The checkout it manages floats on main
        # and moves with `hermes update`, matching how Hermes runs on the Pi;
        # rerunning hermes-desktop-setup is the documented update path.
        installer = pkgs.fetchurl {
          url = "https://hermes-agent.nousresearch.com/install.sh";
          hash = "sha256-9M2w4g8ayiw4cadrli/U22FRD1Sc+XN1nHU6wTNJvrU=";
        };

        # Upstream app icon (apps/desktop/assets/icon.png) for the launcher
        # entry; the built desktop app ships the same artwork.
        icon = pkgs.fetchurl {
          url = "https://raw.githubusercontent.com/NousResearch/hermes-agent/main/apps/desktop/assets/icon.png";
          hash = "sha256-LmndmoodP54/Yn78NxAq7UFvcD4i9ZnjHF2GshKk1t4=";
        };

        # In-env runner: resolves the newest release artifact at runtime and
        # execs it inside the FHS sandbox. Passed as runScript so the
        # generated /init execs a real program instead of `bash "$@"`.
        hermesDesktopInner = pkgs.writeShellScript "hermes-desktop-inner" ''
          release="$HOME/.hermes/hermes-agent/apps/desktop/release"
          # Upstream's own Linux install path packages with electron-builder
          # --dir, producing release/linux-unpacked/{h,H}ermes — no AppImage.
          # Prefer an AppImage if one ever appears, else the unpacked binary.
          app="$(find "$release" -maxdepth 1 -name '*.AppImage' -printf '%T@\t%p\n' 2>/dev/null \
              | sort -rn | head -n 1 | cut -f2-)" || app=""
          if [ -n "$app" ]; then
            # electron-updater keys in-place updates off APPIMAGE; point it
            # at the newest bundle so its rewrite lands where the glob looks.
            export APPIMAGE="$app"
            exec appimage-exec.sh -w "$app" -- "$@"
          fi
          for name in hermes Hermes; do
            if [ -x "$release/linux-unpacked/$name" ]; then
              exec "$release/linux-unpacked/$name" "$@"
            fi
          done
          echo "Hermes Desktop is not built yet; run: hermes-desktop-setup" >&2
          exit 1
        '';

        # appimage-run's FHS env plus appimage-exec (runs AppImages with
        # writable home; dev.nix's openresearch chroot adds it the same
        # way) and libsecret (Electron safeStorage, the one lib upstream .deb
        # packaging adds beyond the AppImage's own bundle).
        hermesFhs = pkgs.buildFHSEnv (
          pkgs.appimageTools.defaultFhsEnvArgs
          // {
            name = "hermes-desktop-fhs";
            runScript = "${hermesDesktopInner}";
            targetPkgs =
              ppkgs:
              [
                pkgs.appimageTools.appimage-exec
              ]
              ++ pkgs.appimageTools.defaultFhsEnvArgs.targetPkgs ppkgs
              ++ [
                ppkgs.libsecret
              ];
          }
        );

        hermesDesktopSetup = pkgs.writeShellApplication {
          name = "hermes-desktop-setup";
          # gnumake/gcc/binutils: node-gyp compiles native modules (node-pty
          # ships no linux-x64 prebuild for current node) and NixOS has no
          # system toolchain for the installer to fall back on.
          runtimeInputs = [
            pkgs.coreutils
            pkgs.curl
            pkgs.git
            pkgs.gnumake
            pkgs.gcc
            pkgs.binutils
          ];
          text = ''
            # Idempotent: a rerun updates the existing checkout and rebuilds
            # the products, so this doubles as the update command.
            exec bash ${installer} --include-desktop --non-interactive "$@"
          '';
        };

        hermesDesktopRun = pkgs.writeShellApplication {
          name = "hermes-desktop";
          runtimeInputs = [ pkgs.coreutils ];
          text = ''
            # Desktop SSH connects with keys only (BatchMode ssh, no password
            # fallback), so a launcher that carries no agent socket leaves it
            # unable to authenticate. Fall back to the 1Password agent when
            # SSH_AUTH_SOCK is unset and its socket exists.
            if [ -z "''${SSH_AUTH_SOCK:-}" ] && [ -S "$HOME/.1password/agent.sock" ]; then
              export SSH_AUTH_SOCK="$HOME/.1password/agent.sock"
            fi
            exec ${hermesFhs}/bin/hermes-desktop-fhs "$@"
          '';
        };

        desktopItem = pkgs.makeDesktopItem {
          name = "hermes-desktop";
          desktopName = "Hermes Desktop";
          comment = "Native desktop shell for the Hermes agent";
          exec = "${hermesDesktopRun}/bin/hermes-desktop";
          icon = "${icon}";
          terminal = false;
          categories = [
            "Development"
            "ArtificialIntelligence"
          ];
          mimeTypes = [ "x-scheme-handler/hermes" ];
        };
      in
      {
        home.packages = [
          hermesDesktopSetup
          hermesDesktopRun
          desktopItem
        ];
      };
  };
}
