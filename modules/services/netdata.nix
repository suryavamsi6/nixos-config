# Netdata monitoring agent (loopback-only, LAN door is Caddy).
#
# Extracted verbatim from modules/hosts/nixos-homelab.nix as the first step of
# plans/clan-deploy-rs-migration.md §7. Nothing in the service definition
# changed: the drvPath is identical before and after the move, which is the
# gate that proves the extraction was mechanical.
#
# Collected metrics: CPU, RAM, network, disk, temperatures, cgroups (so Incus
# guests show up as containers) and the apps plugin. It is not claimed to
# Netdata Cloud and does not phone home. The dashboard has no login at all, so
# it must not be reachable by anything that is not already trusted: it binds
# the loopback only (the `incusbr0` trusted interface covers containers) and
# Caddy is the only way in from the LAN, as netdata.home.arpa. Do not put this
# on the tailnet funnel.
{ lib, ... }:
{
  options.flake.modules.nixos.netdata = lib.mkOption {
    type = lib.types.deferredModule;
    default = { pkgs, ... }: {
      services.netdata = {
        enable = true;
        # pkgs.netdata is built with the dashboard off (withCloudUi
        # defaults false). The agent then answers :19999 and
        # /api/v1/info, but every page is "File does not exist".
        # netdataCloud is the same agent plus the local dashboard.
        # It is not a cloud claim; enableAnalyticsReporting stays off.
        package = pkgs.netdataCloud;
        enableAnalyticsReporting = false;
        config = {
          web = {
            # Loopback only: :19999 used to be open on the LAN with no
            # authentication whatsoever. Caddy proxies netdata.home.arpa
            # from 127.0.0.1:19999; containers reach it over incusbr0.
            "bind to" = "127.0.0.1:19999";
            "allow connections from" = "localhost 10.* 192.168.* 100.*";
          };
          global = {
            "memory mode" = "dbengine";
            "update every" = 1;
          };
          "plugin:cgroups" = {
            "enable cgroup name resolving" = "yes";
          };
        };
      };
    };
  };
}
