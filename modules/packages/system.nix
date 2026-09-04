# System utilities (NixOS)
{ lib, ... }:
{
  options.flake.modules.nixos.system = lib.mkOption {
    type = lib.types.deferredModule;
    default = { pkgs, inputs, ... }:
    let
      qsPkg = inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default;
      qtQml = pkg: "${pkg}/lib/qt-6/qml";
      qmlPaths = pkgs.lib.concatStringsSep ":" [
        (qtQml pkgs.kdePackages.qt5compat)
        (qtQml pkgs.kdePackages.qtmultimedia)
        (qtQml pkgs.kdePackages.qtwebsockets)
        (qtQml pkgs.kdePackages.qtwebengine)
      ];
      # Serpantinum QML needs Qt5Compat, Multimedia, WebSockets, WebEngine
      qsWrapped = pkgs.runCommand "quickshell-with-qml" {
        nativeBuildInputs = [ pkgs.makeWrapper ];
        meta.mainProgram = "qs";
      } ''
        mkdir -p $out/bin
        for bin in qs quickshell; do
          if [ -e "${qsPkg}/bin/$bin" ]; then
            makeWrapper "${qsPkg}/bin/$bin" "$out/bin/$bin" \
              --prefix NIXPKGS_QT6_QML_IMPORT_PATH : "${qmlPaths}" \
              --prefix QML2_IMPORT_PATH : "${qmlPaths}"
          fi
        done
      '';
    in
    {
      environment.systemPackages = with pkgs; [
        pavucontrol
        pulseaudio
        xdg-user-dirs
        superfile
        nautilus
        nautilus-open-any-terminal
        lm_sensors
        p7zip
        cheese
        cameractrls-gtk4
        comfyui
        nodejs
        glance
        sbctl
        (kodi-wayland.withPackages (kodiPkgs: with kodiPkgs; [
          inputstream-adaptive
          inputstreamhelper
          netflix
        ]))
        qsWrapped
      ];

      nix.nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];

      services.upower.enable = true;
      services.blueman.enable = true;
      zramSwap = {
        enable = true;
        memoryPercent = 25;
        algorithm = "zstd";
      };
      systemd.oomd = {
        enable = true;
        enableRootSlice = true;
        enableUserSlices = true;
      };
      services.ollama = {
        enable = true;
        package = pkgs.ollama-cuda;
        environmentVariables = {
          OLLAMA_KEEP_ALIVE = "5m";
          OLLAMA_NUM_PARALLEL = "1";
          OLLAMA_MAX_LOADED_MODELS = "1";
          OLLAMA_LLM_LIBRARY = "cuda_v12";
          LD_LIBRARY_PATH = "${pkgs.ollama-cuda}/lib/ollama:${pkgs.ollama-cuda}/lib/ollama/cuda_v12:/run/opengl-driver/lib";
        };
      };
      systemd.services.ollama.serviceConfig = {
        CPUQuota = "200%";
        DeviceAllow = lib.mkAfter [ "/dev/nvidia0 rwm" ];
        PrivateUsers = lib.mkForce false;
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
