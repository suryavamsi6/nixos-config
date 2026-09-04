# Host: NixOS Hyprland (x86_64-linux)
{ config, inputs, ... }:
{
  flake.nixosConfigurations.nixos = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = {
      inherit inputs;
      system = "x86_64-linux";
    };
    modules = with config.flake.modules; [
      # Hardware
      nixos.hardwareHyprland
      nixos.nvidia
      nixos.gcb200
      nixos.openrgb

      # Core system
      nixos.boot
      nixos.nixSettings
      nixos.users
      nixos.networking
      nixos.environment
      nixos.shell
      nixos.fonts
      nixos.audio
      nixos.greetd

      # Desktop
      nixos.hyprland
      nixos.serpantinum

      # Packages
      nixos.gaming
      nixos.social
      nixos.system
      nixos.work
      nixos.hermesDesktop

      # External modules
      inputs.chaotic.nixosModules.default

      nixos.locale

      # Host-specific config
      (
        {
          config,
          lib,
          pkgs,
          ...
        }:
        {
          boot.kernelPackages = pkgs.linuxPackages_cachyos;
          hardware.nvidia.package = lib.mkForce pkgs.linuxPackages_cachyos.nvidiaPackages.cachyos;


          networking.hostName = "nixos";

          nixpkgs.config.permittedInsecurePackages = [
            "libxml2-2.13.8"
            "libsoup-2.74.3"
          ];
          services.flatpak.enable = true;
          services.logind = {
            settings.Login.HandleLidSwitch = "ignore";
            settings.Login.HandleLidSwitchExternalPower = "ignore";
            settings.Login.HandleLidSwitchDocked = "ignore";
            settings.Login.KillUserProcesses = true;
          };

          system.nixos.tags = [ "cachyos" ];
          system.stateVersion = "24.11";
        }
      )

      # Home Manager
      inputs.home-manager.nixosModules.home-manager
      {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.backupFileExtension = "bak";
        home-manager.extraSpecialArgs = {
          inherit inputs;
          system = "x86_64-linux";
        };
        home-manager.users.surya = { pkgs, ... }: {
          imports = with config.flake.modules; [
            homeManager.shell
            homeManager.hyprland
            homeManager.serpantinum
            homeManager.wallpapers
            homeManager.dev
            homeManager.work
            homeManager.gaming
          ];

          home.username = "surya";
          home.homeDirectory = "/home/surya";
          home.stateVersion = "24.11";
          programs.home-manager.enable = true;

          home.packages = [
            inputs.zen-browser.packages."x86_64-linux".twilight
            inputs.helium-browser.packages."x86_64-linux".helium
            pkgs.chromium
            pkgs.localsend
          ];
        };
      }
    ];
  };
}
