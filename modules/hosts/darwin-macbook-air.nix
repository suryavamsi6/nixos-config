# Host: Darwin MacBook Air (aarch64-darwin)
{ config, inputs, ... }:
{
  flake.darwinConfigurations.macbook-air = inputs.nix-darwin.lib.darwinSystem {
    system = "aarch64-darwin";
    specialArgs = { inherit inputs; system = "aarch64-darwin"; };
    modules = with config.flake.modules; [
      # Darwin system modules
      darwin.nixSettings
      darwin.users
      darwin.shell
      darwin.fonts
      darwin.defaults
      darwin.security
      darwin.homebrew

      # Host-specific config
      ({ pkgs, ... }: {
        networking.hostName = "macbook-air";
        time.timeZone = "Asia/Calcutta";

        environment.systemPackages = with pkgs; [ vim ];

        nixpkgs.hostPlatform = "aarch64-darwin";
        system.stateVersion = 6;
      })

      # Home Manager
      inputs.home-manager.darwinModules.home-manager
      {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.backupFileExtension = "bak";
        home-manager.extraSpecialArgs = { inherit inputs; system = "aarch64-darwin"; };
        home-manager.users.suryavamsi = { lib, ... }: {
          imports = with config.flake.modules; [
            homeManager.shellDarwin
            homeManager.devDarwin
          ];

          home.username = "suryavamsi";
          home.homeDirectory = lib.mkForce "/Users/suryavamsi";
          home.stateVersion = "24.11";
          programs.home-manager.enable = true;
          home.packages = [ ];
        };
      }
    ];
  };
}
