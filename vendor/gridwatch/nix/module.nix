{ config, lib, pkgs, defaultPackage ? null, ... }:
let
  cfg = config.services.gridwatch;
in {
  options.services.gridwatch = {
    enable = lib.mkEnableOption "Gridwatch APC UPS manager";
    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = defaultPackage;
      defaultText = lib.literalExpression "self.packages.${pkgs.system}.default";
      description = "Gridwatch package containing the desktop app and system agent.";
    };
    group = lib.mkOption {
      type = lib.types.str;
      default = "gridwatch";
      description = "Group allowed to connect to the local read-only agent socket.";
    };
    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "alice" ];
      description = "Existing users to add to the Gridwatch socket group.";
    };
    enableApcupsd = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Let Gridwatch enable apcupsd; disabled by default to avoid changing existing setups.";
    };
    manageShutdownPolicy = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Point apcupsd at a Gridwatch-owned runtime configuration so saved shutdown thresholds are enforced atomically with health verification and rollback.";
    };
  };

  config = lib.mkIf (cfg.enable && cfg.package != null) {
    users.groups.${cfg.group} = { };
    users.users = lib.genAttrs cfg.users (_: { extraGroups = [ cfg.group ]; });

    environment.etc."gridwatch/apcupsd.template" = lib.mkIf (cfg.enableApcupsd && cfg.manageShutdownPolicy) {
      mode = "0640";
      text = ''
        ## apcupsd.conf v1.1 ##
        ${config.services.apcupsd.configText}
        SCRIPTDIR ${pkgs.apcupsd}/etc/apcupsd
      '';
    };

    environment.etc."polkit-1/actions/org.gridwatch.policy".source = ./gridwatch.policy;
    security.polkit.enable = true;
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == "org.gridwatch.maintenance" && subject.isInGroup("${cfg.group}")) {
          return polkit.Result.AUTH_ADMIN_KEEP;
        }
      });
    '';

    systemd.services.gridwatch-agent = {
      description = "Gridwatch UPS monitoring agent";
      wantedBy = [ "multi-user.target" ];
      wants = lib.optional cfg.enableApcupsd "apcupsd.service";
      after = [ "polkit.service" ] ++ lib.optional cfg.enableApcupsd "apcupsd.service";
      environment = {
        GRIDWATCH_APCACCESS = "${pkgs.apcupsd}/bin/apcaccess";
        GRIDWATCH_PKCHECK = "${pkgs.polkit}/bin/pkcheck";
        GRIDWATCH_APC_EVENTS = "/var/log/apcupsd.events";
      } // lib.optionalAttrs (cfg.enableApcupsd && cfg.manageShutdownPolicy) {
        GRIDWATCH_APCUPSD_CONFIG = "/var/lib/gridwatch/apcupsd.conf";
        GRIDWATCH_APCUPSD_TEMPLATE = "/etc/gridwatch/apcupsd.template";
        GRIDWATCH_SYSTEMCTL = "${config.systemd.package}/bin/systemctl";
      };
      serviceConfig = {
        ExecStart = "${cfg.package}/libexec/gridwatch-agent";
        Restart = "on-failure";
        RestartSec = "3s";

        User = "root";
        Group = cfg.group;
        UMask = "0007";
        RuntimeDirectory = "gridwatch";
        RuntimeDirectoryMode = "0770";
        StateDirectory = "gridwatch";
        StateDirectoryMode = "0750";

        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        PrivateMounts = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "ptraceable";
        ProcSubset = "all";
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        RemoveIPC = true;
        CapabilityBoundingSet = "";
        AmbientCapabilities = "";
        SystemCallArchitectures = "native";
        RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
        IPAddressDeny = "any";
        IPAddressAllow = [ "localhost" ];
        ReadOnlyPaths = [ "-/var/log/apcupsd.events" ];
        ReadWritePaths = [ "/run/gridwatch" "/var/lib/gridwatch" ];
      };
    };

    services.apcupsd.enable = lib.mkIf cfg.enableApcupsd true;

    systemd.services.apcupsd = lib.mkIf (cfg.enableApcupsd && cfg.manageShutdownPolicy) {
      preStart = ''
        install -d -o root -g ${cfg.group} -m 0750 /var/lib/gridwatch
        if [ ! -f /var/lib/gridwatch/apcupsd.conf ]; then
          install -o root -g ${cfg.group} -m 0640 /etc/gridwatch/apcupsd.template /var/lib/gridwatch/apcupsd.conf
        fi
      '';
      serviceConfig.ExecStart = lib.mkForce "${pkgs.apcupsd}/bin/apcupsd -b -f /var/lib/gridwatch/apcupsd.conf -d1";
    };
    systemd.services.apcupsd-killpower = lib.mkIf (cfg.enableApcupsd && cfg.manageShutdownPolicy) {
      serviceConfig.ExecStart = lib.mkForce "${pkgs.apcupsd}/bin/apcupsd --killpower -f /var/lib/gridwatch/apcupsd.conf";
    };
  };
}
