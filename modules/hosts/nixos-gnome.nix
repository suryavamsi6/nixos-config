# Host: NixOS GNOME (x86_64-linux) — the "plasma" configuration
{ config, inputs, ... }:
{
  flake.nixosConfigurations.plasma = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = { inherit inputs; system = "x86_64-linux"; };
    modules = with config.flake.modules; [
      # Hardware
      nixos.hardwareGnome
      nixos.nvidia

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
      nixos.gnome

      # Packages
      nixos.gaming
      nixos.social
      nixos.system

      nixos.locale

      # Host-specific config
      ({ pkgs, ... }: {
        networking.hostName = "nixos";

        nixpkgs.overlays = [ inputs.hyprpanel.overlay ];

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
