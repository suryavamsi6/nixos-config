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
            "https://cache.nixos.org"
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

      # Desktop apps launched from the bar (Steam, waiters) live in the
      # user slice. Stock stop timeouts are 90s–2min, which is the
      # "A stop job is running for User Manager for UID 1000" wait.
      systemd.settings.Manager.DefaultTimeoutStopSec = "15s";
      systemd.user.settings.Manager.DefaultTimeoutStopSec = "8s";

      # googlefonts/nanoemoji retagged v0.16.0; nixpkgs hash is stale and
      # blocks jetbrains-mono -> system fonts -> Steam FHS.
      nixpkgs.overlays = [
        (final: prev: {
          pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
            (pyfinal: pyprev: {
              nanoemoji = pyprev.nanoemoji.overrideAttrs (old: {
                src = old.src.override {
                  hash = "sha256-FysyKC01XBnRiur5RR9fcsTxQqE8x0JJHSoe3q6JtKc=";
                };
              });
            })
          ];
        })
        # `makeBinaryWrapper` now rejects a `--prefix`/`--suffix` value that is
        # empty or begins/ends with the separator (GHSA-p7v3-pr2c-8584): such a
        # segment makes shells, execvp() and the dynamic loader search the
        # current directory. `lazarus` wraps its launcher with
        # `--prefix NIX_LDFLAGS ' ' "$(echo "$NIX_LDFLAGS" | sed -re 's/-rpath
        # [^ ]+//g')"`, and stdenv's `_addRpathPrefix` puts the self-rpath
        # first, so stripping it leaves a leading space and the check aborts
        # `lazarus-qt6` in installPhase with `#error --prefix NIX_LDFLAGS would
        # introduce an empty PATH-like segment`. That takes `goverlay` (which
        # builds against lazarus-qt6) with it.
        # Upstream fixed it in d02c4b3f3dbc ("lazarus: fix build", nixpkgs
        # master 2026-10-01) by trimming that residue; the locked
        # nixos-unstable rev c59305b predates the fix. Remove this overlay
        # after the next nixpkgs bump. `lazarus`/`lazarus-qt5` carry the same
        # line, but nothing here uses them.
        (final: prev: {
          lazarus-qt6 = prev.lazarus-qt6.overrideAttrs (old: {
            postInstall = builtins.replaceStrings
              [ ''$(echo "$NIX_LDFLAGS" | sed -re 's/-rpath [^ ]+//g')'' ]
              [ ''$(echo "$NIX_LDFLAGS" | sed -re 's/-rpath [^ ]+//g' | sed -re 's/(^ *| *$)//g;')'' ]
              old.postInstall;
          });
        })
      ];
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
