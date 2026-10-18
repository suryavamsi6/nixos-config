# System utilities (NixOS)
{ lib, ... }:
{
  options.flake.modules.nixos.system = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { pkgs, inputs, ... }:
      let
        qsPkgBase = inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default;
        # Current Quickshell already handles Hyprland 0.55 workspace addresses.
        # Keep its normal Qt wrapper and only add the QML import paths below.
        qsPkgUnwrapped = qsPkgBase.unwrapped;
        qsPkg = qsPkgBase.overrideAttrs (_: {
          installPhase = ''
            mkdir -p $out
            cp -r ${qsPkgUnwrapped}/* $out
          '';
        });
        qtQml = pkg: "${pkg}/lib/qt-6/qml";
        qmlPaths = pkgs.lib.concatStringsSep ":" [
          (qtQml pkgs.kdePackages.qt5compat)
          (qtQml pkgs.kdePackages.qtmultimedia)
          (qtQml pkgs.kdePackages.qtwebsockets)
          (qtQml pkgs.kdePackages.qtwebengine)
        ];
        qsWrapped =
          pkgs.runCommand "quickshell-with-qml"
            {
              nativeBuildInputs = [ pkgs.makeWrapper ];
              meta.mainProgram = "qs";
            }
            ''
              mkdir -p $out/bin
              for bin in qs quickshell; do
                if [ -e "${qsPkg}/bin/$bin" ]; then
                  makeWrapper "${qsPkg}/bin/$bin" "$out/bin/$bin" \
                    --prefix NIXPKGS_QT6_QML_IMPORT_PATH : "${qmlPaths}" \
                    --prefix QML2_IMPORT_PATH : "${qmlPaths}"
                fi
              done
            '';
        unslothDesktop = pkgs.appimageTools.wrapType2 {
          pname = "unsloth-desktop";
          version = "0.1.908-beta";
          src = pkgs.fetchurl {
            url = "https://github.com/unslothai/unsloth/releases/download/v0.1.908-beta/Unsloth-Desktop-Linux.AppImage";
            hash = "sha256-N7Nzb2zqm/db/zhvr7OuPhVy83Z+AHBng9PpasQVbCs=";
          };
          extraPkgs = pkgs: [ pkgs.libnotify pkgs.libnghttp2 ];
        };
        unslothDesktopEntry = pkgs.makeDesktopItem {
          name = "unsloth";
          desktopName = "Unsloth";
          comment = "Run and train AI models locally";
          exec = "${unslothDesktop}/bin/unsloth-desktop";
          icon = "applications-science";
          terminal = false;
          categories = [ "Development" "Education" ];
        };
        koboldcpp = pkgs.writeShellApplication {
          name = "koboldcpp";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.curl
          ];
          text = ''
            version="1.123.1"
            state_dir="''${XDG_DATA_HOME:-$HOME/.local/share}/koboldcpp"
            binary="$state_dir/koboldcpp-linux-x64"
            tmp="$binary.tmp"
            mkdir -p "$state_dir"

            if [[ ! -x "$binary" ]]; then
              echo "Downloading KoboldCpp $version (prebuilt CUDA binary)..." >&2
              curl --fail --location --retry 3 --retry-all-errors \
                "https://github.com/LostRuins/koboldcpp/releases/download/v$version/koboldcpp-linux-x64" \
                --output "$tmp"
              chmod 0755 "$tmp"
              mv "$tmp" "$binary"
            fi

            exec "$binary" "$@"
          '';
        };
      in {
        environment.systemPackages = with pkgs; [
          pavucontrol
          pulseaudio
          xdg-user-dirs
          superfile
          nautilus
          nautilus-open-any-terminal
          file-roller
          lm_sensors
          p7zip
          unzip
          cheese
          cameractrls-gtk4
          unslothDesktop
          unslothDesktopEntry
          koboldcpp
          nodejs
          obsidian
          bitwarden-desktop
          glance
          sbctl
          (kodi-wayland.withPackages (
            kodiPkgs: with kodiPkgs; [
              inputstream-adaptive
              inputstreamhelper
              netflix
            ]
          ))
          qsWrapped
        ];


        services.upower.enable = true;
        services.blueman.enable = true;
        zramSwap = {
          enable = true;
          memoryPercent = 25;
          algorithm = "zstd";
        };
        # Keep idle/background pages from being pushed into swap aggressively.
        # This avoids kswapd churn and zram write failures on the 32 GiB desktop.
        boot.kernel.sysctl."vm.swappiness" = 10;
        # Desktop sessions run several Chromium/Electron-class file watchers at
        # once (Emdash, Steam's CEF, Zen, editors) and each one adds its own
        # inotify watch per directory. The budget is per UID and counts
        # (instance, inode) pairs, while watches on unlinked inodes stay charged
        # until the owning process exits -- so a few apps over a $HOME-sized
        # tree, plus any stale watches, exhaust it. When that happens `nom`
        # aborts `nh os switch` with
        #   nom: addWatch: resource exhausted (No space left on device)
        # and every other file watcher in the session fails with it. Overrides
        # nixpkgs' lib.mkDefault 524288 (nixos/modules/config/sysctl.nix), which
        # is the value the desktop was saturating. A watch costs roughly 1 KiB of
        # kernel memory, so this ceiling is only reached by a watcher that is
        # itself misbehaving; the scratchpad note records the command that names
        # the top holders.
        boot.kernel.sysctl = {
          "fs.inotify.max_user_watches" = 2097152;
          # Raised from the 16384 default so event bursts are not silently
          # dropped (dropped events look like an editor missing file changes).
          "fs.inotify.max_queued_events" = 65536;
        };
        systemd.oomd = {
          enable = true;
          enableRootSlice = true;
          enableUserSlices = true;
        };

        qt.enable = true;

        # 1Password (system module required for polkit + browser integration)
        programs._1password.enable = true;
        programs._1password-gui = {
          enable = true;
          polkitPolicyOwners = [ "surya" ];
        };

        programs.nh = {
          enable = true;
          flake = "/home/surya/Dotfiles/nixos-config";
        };
      };
  };
}
