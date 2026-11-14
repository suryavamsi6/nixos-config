# Factory Desktop (droid/factory.app) unofficial Linux port, 1.1.0.
#
# Linux has no official Factory Desktop build. The app is assembled locally
# by the ~/Projects/factory-desktop-linux port project, which takes the
# authorized official macOS DMG, swaps in the Linux Electron runtime, patches
# the asar (websocket daemon transport, window controls, native updater
# bridge, ...) and packages a .deb. That deb is the only input this module
# accepts, so nothing proprietary is redistributed here.
#
# Bootstrapping a fresh machine (or after a `nix-collect-garbage` that lost
# the deb):
#
#   cd ~/Projects/factory-desktop-linux
#   nix shell nixpkgs#cargo nixpkgs#rustc nixpkgs#dpkg -c make build-app deb VERSION=1.1.0
#   nix-store --add-root ~/.local/state/nix/user-roots/factory-desktop-deb \
#     --indirect -r "$(nix-store --add-fixed sha256 dist/factory-desktop_1.1.0_amd64.deb)"
#
# The `git add`-able part of this repo is therefore only the module; the
# deb lives in the store and is pinned by the hash in package.nix.
{ lib, ... }:
{
  options.flake.modules.homeManager.factoryDesktopLinux = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { pkgs, ... }:
      let
        factoryDesktopLinux = pkgs.callPackage ./factory-desktop-linux/package.nix { };
      in
      {
        home.packages = [ factoryDesktopLinux ];
      };
  };
}
