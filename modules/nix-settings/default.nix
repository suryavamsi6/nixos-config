# Nix settings — experimental features, GC, unfree, cachix, performance (NixOS + Darwin)
{ lib, ... }:
{
  options.flake.modules.nixos.nixSettings = lib.mkOption {
    type = lib.types.deferredModule;
    default = { pkgs, ... }: {
      nix = {
        package = pkgs.nix;
        settings = {
          experimental-features = [
            "nix-command"
            "flakes"
          ];
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

      # nixpkgs' kmod aggregator always copies modules.cer after depmod
      # (pkgs/os-specific/linux/kmod/aggregator.nix). Chaotic-Nyx CachyOS
      # kernels do not ship that certificate — 7.2.11-cachyos has the
      # modules.* indexes and no modules.cer — so the cp fails
      # linux-*-modules and the whole system closure. Keep the merge for
      # kernels that do ship a certificate. Drop this once nixpkgs guards
      # the copy.
      nixpkgs.overlays = [
        (final: prev: {
          aggregateModules =
            modules:
            (prev.aggregateModules modules).overrideAttrs (old: {
              postBuild =
                let
                  start = "cp --no-preserve=mode,ownership --remove-destination \\";
                  end = "xargs -d'\\n' cat >> modules.cer";
                  withIf =
                    builtins.replaceStrings [ start ] [ "if [ -e modules.cer ]; then\n${start}" ]
                      old.postBuild;
                  patched = builtins.replaceStrings [ end ] [ "${end}\nfi" ] withIf;
                in
                if withIf == old.postBuild || patched == withIf then
                  throw "aggregateModules modules.cer workaround missed its target; nixpkgs aggregator.nix changed"
                else
                  patched;
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
        # aarch64-linux builds run in a local Linux VM on this ARM Mac.
        # The Pi deploy then copies that closure instead of compiling on the Pi.
        linux-builder.enable = true;
        settings = {
          experimental-features = [
            "nix-command"
            "flakes"
          ];
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
