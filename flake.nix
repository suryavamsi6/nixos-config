{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    zen-browser.url = "github:0xc000022070/zen-browser-flake";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprpanel.url = "github:Jas-SinghFSU/HyprPanel";
    hyprpanel.inputs.nixpkgs.follows = "nixpkgs";
    ags.url = "github:aylur/ags";
    chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      home-manager,
      chaotic,
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
            ./systems/x86_64-linux/default/configuration.nix
            chaotic.nixosModules.default
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.surya = import ./systems/x86_64-linux/default/home.nix;
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

        plasma = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            inherit inputs;
            system = "x86_64-linux";
          };
          modules = [
            ./systems/x86_64-linux/gnome/configuration.nix
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.surya = import ./systems/x86_64-linux/gnome/home.nix;
              home-manager.extraSpecialArgs = {
                inherit inputs;
                system = "x86_64-linux";
              };
              home-manager.backupFileExtension = "bak";
            }
            { nixpkgs.overlays = [ inputs.hyprpanel.overlay ]; }
          ];

        };

      };
    };
}
