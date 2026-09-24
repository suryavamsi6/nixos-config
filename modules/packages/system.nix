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
          version = "0.1.806-beta";
          src = pkgs.fetchurl {
            url = "https://github.com/unslothai/unsloth/releases/download/v0.1.806-beta/Unsloth-Desktop-Linux.AppImage";
            hash = "sha256-Qm9q0GaxuxkcFJfwlLXZy2r9B1QUmb2OJrMdpeiWyBY=";
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
        koboldcppCuda =
          (pkgs.koboldcpp.override {
            # RTX 5080 (Blackwell, compute capability 12.0).
            config = pkgs.config // { cudaSupport = true; };
            cublasSupport = true;
            cudaArches = [ "sm_120" ];
          }).overrideAttrs (old: {
            nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.patchelf ];
            postFixup = (old.postFixup or "") + ''
              # Nixpkgs removes -lcuda at link time, but current KoboldCpp calls the
              # CUDA driver API directly. Load the real NixOS driver at runtime.
              patchelf --add-needed libcuda.so.1 "$out/bin/koboldcpp_cublas.so"
            '';
          });
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
          koboldcppCuda
          comfyui
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
