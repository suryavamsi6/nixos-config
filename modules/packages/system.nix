# System utilities (NixOS)
{ lib, ... }:
{
  options.flake.modules.nixos.system = lib.mkOption {
    type = lib.types.deferredModule;
    default = { pkgs, inputs, ... }: {
      environment.systemPackages = with pkgs; [
        polychromatic
        pavucontrol
        openrgb
        superfile
        toybox
        nautilus
        nautilus-open-any-terminal
        lm_sensors
        p7zip
        unzip
        blueman
        floorp-bin
        cheese
        cameractrls-gtk4
        nodejs
        glance
        sbctl
        flatpak-builder
        niv
        inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default
        elephant
      ];

      nix.nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];

      services.upower.enable = true;

      hardware.openrazer.enable = false;
      qt.enable = true;

      # 1Password (system module required for polkit + browser integration)
      programs._1password.enable = true;
      programs._1password-gui = {
        enable = true;
        polkitPolicyOwners = [ "surya" ];
      };

      programs.nh = {
        enable = true;
        flake = "/home/$USER/Dotfiles/nixos-config";
      };
    };
  };
}
