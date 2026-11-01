# Host: Darwin MacBook Air (aarch64-darwin)
#
# Two things live here on purpose:
#
#   * `flake.modules.darwin.macbookAir` — the reusable host body. This is the
#     unit Clan evaluates once the migration flips (see
#     plans/clan-deploy-rs-migration.md §4).
#   * `flake.darwinConfigurations.macbook-air` — the transitional wrapper that
#     instantiates the body with nix-darwin. It is deleted in the flip step, and
#     exists only so the host keeps building from an unchanged drvPath.
{ config, inputs, lib, ... }:
{
  options.flake.modules.darwin.macbookAir = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { flakeModules, ... }:
      {
      imports = with flakeModules; [
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
            imports = with flakeModules; [
              homeManager.shellDarwin
              homeManager.pi
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
  };
}
