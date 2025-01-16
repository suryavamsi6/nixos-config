{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    zen-browser.url = "github:0xc000022070/zen-browser-flake";
    hyprland.url = "github:hyprwm/Hyprland";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprpanel.url = "github:Jas-SinghFSU/HyprPanel";
    hyprpanel.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      home-manager,
      ...
    }:
    {
      nixosConfigurations = {
        nixos = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            inherit inputs;
            system = "x86_64-linux";
          };
          modules = [
            ./hosts/default/configuration.nix
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.surya = import ./hosts/default/home.nix;
              home-manager.extraSpecialArgs = {
                inherit inputs;
                system = "x86_64-linux";
              };
              home-manager.backupFileExtension = "backup";
              # Optionally, use home-manager.extraSpecialArgs to pass
              # arguments to home.nix
            }
            { nixpkgs.overlays = [ inputs.hyprpanel.overlay ]; }
          ];
        };

        plasma = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            inherit inputs;
            system = "x86_64-linux";
          };
          modules = [
            ./hosts/plasma/configuration.nix
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.surya = import ./hosts/plasma/home.nix;
              home-manager.extraSpecialArgs = {
                inherit inputs;
                system = "x86_64-linux";
              };
              home-manager.backupFileExtension = "bak";
              # Optionally, use home-manager.extraSpecialArgs to pass
              # arguments to home.nix
            }
            { nixpkgs.overlays = [ inputs.hyprpanel.overlay ]; }
          ];

        };

      };
    };
}
