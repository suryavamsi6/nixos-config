# NUT server (upsd) that re-exports the UPS apcupsd already owns.
#
# The UPS hangs off this host's USB bus and apcupsd owns it exclusively —
# gridwatch's whole design depends on being the only reader. A NUT driver
# cannot open the same device, so the bridge goes the other way: apcupsd is
# itself a NUT-compatible server on its NIS port (3551), and NUT ships the
# `apcupsd-ups` client driver for exactly that peer. Nutify's wizard expects a
# real NUT server on 3493, so publish standard NUT and leave ownership alone:
#
#   apcupsd --(USB)--> NIS 127.0.0.1:3551
#                         |  apcupsd-ups driver (one UPS)
#                         v
#                       upsd 0.0.0.0:3493  (this module)
#                         |  LAN
#                         v
#                   Nutify on homelab (Remote NUT Only)
#
# Verified end to end with this exact driver/upsd invocation:
#   upsc back-ups-rs-1500g-in@<host>:3493
#   battery.charge: 100.0 / status: ONLINE / device.mfr: APC
{ lib, ... }:
{
  options.flake.modules.nixos.nutServer = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { pkgs, ... }:
      let
        # Same identifier apcupsd exports. NUT clients address it as
        # `<name>@<host>`, so keeping it identical means one UPS name across
        # apcupsd, NUT and Nutify.
        upsName = "back-ups-rs-1500g-in";

        upsConf = pkgs.writeText "ups.conf" ''
          # `port` is the apcupsd NIS endpoint, not a serial device.
          [${upsName}]
            driver = apcupsd-ups
            port = 127.0.0.1:3551
            desc = "APC Back-UPS RS 1500G-IN (re-exported from apcupsd)"
        '';

        upsdConf = pkgs.writeText "upsd.conf" ''
          # Read-only relay for the LAN. Nothing on this host runs upsmon
          # against it, so the only privileged LISTEN to worry about is the
          # absent one: no admin commands are granted below.
          LISTEN 0.0.0.0 3493
          MAXAGE 25
        '';

        # upsd exits at startup if this file is missing ("stat upsd.users: No
        # such file or directory" then cleanup) even when no user is needed.
        # It stays empty: Nutify only polls status, so no auth is granted.
        upsdUsers = pkgs.writeText "upsd.users" ''
          # Intentionally empty. Status reads (LIST/GET) need no account;
          # this file exists because upsd refuses to start without it.
        '';

        # NUT reads its config from $NUT_CONFPATH, which keeps every file
        # declarative in the store instead of under /etc. All three files
        # must live in that one directory.
        confDir = pkgs.runCommand "nut-conf" { } ''
          mkdir -p $out
          cp ${upsConf} $out/ups.conf
          cp ${upsdConf} $out/upsd.conf
          cp ${upsdUsers} $out/upsd.users
          chmod 0755 $out
          chmod 0644 $out/ups.conf $out/upsd.conf
          chmod 0640 $out/upsd.users
        '';

        env = {
          NUT_CONFPATH = "${confDir}";
          NUT_STATEPATH = "/run/nut";
        };
      in
      {
        # `upsc` for debugging the relay from this host:
        #   upsc ${upsName}@localhost
        environment.systemPackages = [ pkgs.nut ];

        # systemd's User= needs the account to exist before ExecStart runs.
        users.groups.nut = { };
        users.users.nut = {
          isSystemUser = true;
          group = "nut";
          description = "Network UPS Tools";
        };

        # Runtime only: the driver socket, upsd's pid, and the state files
        # NUT rewrites. Config comes from the store above, so nothing here
        # is worth surviving a reboot.
        systemd.tmpfiles.rules = [
          "d /run/nut 0755 nut nut -"
        ];

        systemd.services.nut-server = {
          description = "NUT driver for the apcupsd-exported APC UPS";
          wantedBy = [ "multi-user.target" ];
          after = [
            "apcupsd.service"
            "network.target"
          ];
          wants = [ "apcupsd.service" ];
          # Read-only relay: retry forever rather than staying dead. apcupsd
          # is restarted whenever gridwatch rewrites the policy, and the
          # driver drops its socket with it.
          startLimitIntervalSec = 0;
          serviceConfig = {
            Type = "simple";
            User = "nut";
            Group = "nut";
            # Foreground directly instead of through upsdrvctl: systemd then
            # tracks the real driver process, and a driver crash is visible
            # as a unit failure rather than a stale background child.
            #
            # -u/-g are mandatory here: nixpkgs' nut is built
            # --with-user=nutmon --with-group=nutmon, so both the driver and
            # upsd try to setuid to a `nutmon` account that does not exist and
            # die at startup with "OS user nutmon not found". Naming the
            # account explicitly keeps NUT's privilege drop and matches the
            # unit's User=/Group=.
            ExecStart = "${pkgs.nut}/bin/apcupsd-ups -a ${upsName} -u nut -g nut -F";
            Restart = "always";
            RestartSec = "10s";
          };
          environment = env;
        };

        systemd.services.nut-upsd = {
          description = "NUT network server (upsd)";
          wantedBy = [ "multi-user.target" ];
          after = [ "nut-server.service" ];
          requires = [ "nut-server.service" ];
          startLimitIntervalSec = 0;
          serviceConfig = {
            Type = "simple";
            User = "nut";
            Group = "nut";
            # Same nutmon override as the driver (see nut-server above).
            ExecStart = "${pkgs.nut}/bin/upsd -u nut -F";
            Restart = "always";
            RestartSec = "10s";
          };
          environment = env;
        };

        # 3493 to the LAN only. homelab's Nutify container reaches this over
        # 192.168.0.243 (the Incus bridge cannot see the host loopback),
        # which is the single path that needs to work. No NIS port is opened:
        # apcupsd's own 3551 stays on loopback.
        networking.firewall.allowedTCPPorts = [ 3493 ];
      };
  };
}
