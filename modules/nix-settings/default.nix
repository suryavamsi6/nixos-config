# Nix settings — experimental features, GC, unfree, cachix (NixOS + Darwin)
{ lib, ... }:
{
  options.flake.modules.nixos.nixSettings = lib.mkOption {
    type = lib.types.deferredModule;
    default = { pkgs, ... }: {
      nix = {
        package = pkgs.nix;
        settings = {
          experimental-features = [ "nix-command" "flakes" ];
          auto-optimise-store = true;
          substituters = [ "https://hyprland.cachix.org" ];
          trusted-public-keys = [ "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc=" ];
        };
        gc = {
          automatic = true;
          dates = "weekly";
          options = "--delete-older-than 7d";
        };
      };
      nixpkgs.config.allowUnfree = true;
    };
  };

  options.flake.modules.darwin.nixSettings = lib.mkOption {
    type = lib.types.deferredModule;
    default = { pkgs, ... }: {
      nix = {
        package = pkgs.nix;
        settings = {
          experimental-features = [ "nix-command" "flakes" ];
        };
        optimise.automatic = true;
        gc = {
          automatic = true;
          interval = {
            Weekday = 0;
            Hour = 2;
            Minute = 0;
          };
          options = "--delete-older-than 7d";
        };
      };
      nixpkgs.config.allowUnfree = true;
    };
  };
}
