# OpenBot desktop app (openbot.run).
#
# The homelab already runs OpenBot's hosted server in an Incus container
# (systemd.services.incus-openbot in nixos-homelab.nix); this module installs
# the Electron app that signs in to that account, so it only belongs on a
# desktop host. The package itself is the pinned release AppImage — see
# openbot-desktop.nix.
{ lib, ... }:
{
  options.flake.modules.homeManager.openbot = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { pkgs, ... }:
      let
        openbot = pkgs.callPackage ./openbot-desktop.nix { };
      in
      {
        home.packages = [ openbot ];

        # The package ships a working entry (Exec=openbot), but the app writes
        # its own entry into XDG_DATA_HOME once it registers deep links, and
        # XDG_DATA_HOME is searched before the profile. A copy left behind by a
        # manual upstream AppImage run points at AppRun, which cannot start on
        # NixOS, so pin the entry here. force = true so an existing regular file
        # does not abort activation.
        xdg.dataFile."applications/openbot.desktop" = {
          source = "${openbot}/share/applications/openbot.desktop";
          force = true;
        };
      };
  };
}
