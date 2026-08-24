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
        superfile
        nautilus
        nautilus-open-any-terminal
        lm_sensors
        p7zip
        unzip
        blueman
        cheese
        cameractrls-gtk4
        nodejs
        glance
        sbctl
        stremio-linux-shell
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
