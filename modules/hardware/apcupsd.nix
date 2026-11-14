# Plain apcupsd for the APC Back-UPS RS 1500G on this host's USB bus.
#
# This replaces the Gridwatch agent, which used to own the runtime apcupsd
# configuration and re-render BATTERYLEVEL/MINUTES on every policy change. The
# policy is now static and lives in the file below; there is no agent, no
# polkit surface, and no /var/lib/gridwatch state to keep in sync.
#
# The thresholds are unchanged from what Gridwatch enforced (5% battery or
# 1 minute on battery), so the shutdown behaviour on power loss is identical.
#
# apcupsd owns the USB device exclusively. `modules/monitoring/nut-server.nix`
# re-exports it over the NUT protocol by talking to this daemon's NIS port
# rather than opening the device a second time — do not add a second reader.
{ lib, ... }:
{
  options.flake.modules.nixos.apcupsd = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { ... }:
      {
        services.apcupsd.enable = true;

        # Shutdown policy: power off at 5% battery or after 1 minute on
        # battery, whichever comes first. Local-only NIS (127.0.0.1:3551) is
        # what nut-server bridges to standard NUT on 3493 for Nutify.
        services.apcupsd.configText = ''
          UPSNAME back-ups-rs-1500g-in
          UPSCABLE usb
          UPSTYPE usb
          DEVICE
          POLLTIME 30
          LOCKFILE /run/lock
          PWRFAILDIR /run/apcupsd
          NOLOGINDIR /run/apcupsd
          ONBATTERYDELAY 6
          BATTERYLEVEL 5
          MINUTES 1
          TIMEOUT 0
          NETSERVER on
          NISIP 127.0.0.1
          NISPORT 3551
          EVENTSFILE /var/log/apcupsd.events
          EVENTSFILEMAX 10
        '';
      };
  };
}
