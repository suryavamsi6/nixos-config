# Nix settings — experimental features, GC, unfree, cachix, performance (NixOS + Darwin)
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
          substituters = [
            "https://hyprland.cachix.org"
            "https://nix-community.cachix.org"
          ];
          trusted-public-keys = [
            "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
            "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
          ];
          # Performance: use all cores for builds
          max-jobs = "auto";
          # Allow fetching from binary caches in parallel
          http-connections = 50;
          # Warn about dirty Git trees
          warn-dirty = false;
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
          # Performance: use all cores for builds
          max-jobs = "auto";
          http-connections = 50;
          warn-dirty = false;
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
