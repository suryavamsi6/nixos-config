# Host: NixOS Hyprland (x86_64-linux)
{ config, inputs, ... }:
{
  flake.nixosConfigurations.nixos = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = { inherit inputs; system = "x86_64-linux"; };
    modules = with config.flake.modules; [
      # Hardware
      nixos.hardwareHyprland
      nixos.nvidia

      # Core system
      nixos.boot
      nixos.nixSettings
      nixos.users
      nixos.networking
      nixos.samba
      nixos.environment
      nixos.shell
      nixos.fonts
      nixos.audio
      nixos.greetd

      # Desktop
      nixos.hyprland

      # Packages
      nixos.gaming
      nixos.social
      nixos.system

      # External modules
      inputs.chaotic.nixosModules.default

      # Host-specific config
      ({ pkgs, ... }: {
        networking.hostName = "nixos";
        time.timeZone = "Asia/Kolkata";

        nixpkgs.config.permittedInsecurePackages = [
          "libxml2-2.13.8"
          "libsoup-2.74.3"
        ];

        i18n.defaultLocale = "en_IN";
        i18n.extraLocaleSettings = {
          LC_ADDRESS = "en_IN";
          LC_IDENTIFICATION = "en_IN";
          LC_MEASUREMENT = "en_IN";
          LC_MONETARY = "en_IN";
          LC_NAME = "en_IN";
          LC_NUMERIC = "en_IN";
          LC_PAPER = "en_IN";
          LC_TELEPHONE = "en_IN";
          LC_TIME = "en_IN";
        };

        services.xserver.xkb = {
          layout = "us";
          variant = "";
        };

        services.logind = {
          settings.Login.HandleLidSwitch = "ignore";
          settings.Login.HandleLidSwitchExternalPower = "ignore";
          settings.Login.HandleLidSwitchDocked = "ignore";
        };

        system.stateVersion = "24.11";
      })

      # Home Manager
      inputs.home-manager.nixosModules.home-manager
      {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.backupFileExtension = "bak";
        home-manager.extraSpecialArgs = { inherit inputs; system = "x86_64-linux"; };
        home-manager.users.surya = { ... }: {
          imports = with config.flake.modules; [
            homeManager.shell
            homeManager.hyprland
            homeManager.hyprlock
            homeManager.hyprpaper
            homeManager.swaync
            homeManager.walker
            homeManager.ags
            homeManager.wallpapers
            homeManager.gtkTheme
            homeManager.dev
            homeManager.work
          ];

          home.username = "surya";
          home.homeDirectory = "/home/surya";
          home.stateVersion = "24.11";
          programs.home-manager.enable = true;

          home.packages = with inputs.nixpkgs.legacyPackages.x86_64-linux; [
            inputs.zen-browser.packages."x86_64-linux".twilight-official
          ];
        };
      }
    ];
  };
}
