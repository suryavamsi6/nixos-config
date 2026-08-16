# Networking — NetworkManager, samba (NixOS)
{ lib, ... }:
{
  options.flake.modules.nixos.networking = lib.mkOption {
    type = lib.types.deferredModule;
    default = { ... }: {
      networking.networkmanager = {
        enable = true;
        wifi.powersave = false;
      };
      # Steam probes IPv6, then logs "downgrading to ipv4-only" and the
      # download falls to ~2 Mbps. This host has no global IPv6 anyway.
      networking.enableIPv6 = false;
      boot.kernelModules = [ "tcp_bbr" ];
      boot.kernel.sysctl = {
        "net.core.default_qdisc" = "fq";
        "net.core.rmem_max" = 16777216;
        "net.ipv4.tcp_congestion_control" = "bbr";
        "net.ipv4.tcp_slow_start_after_idle" = 0;
        "net.ipv4.tcp_mtu_probing" = 1;
        # Linux Steam reads sockets in tiny chunks; autotune then shrinks
        # rcv_wnd to ~180KB (~19 Mbps/conn at 85ms). Leave autotune off so
        # the 1MB default window stays advertised.
        "net.ipv4.tcp_moderate_rcvbuf" = 0;
        "net.ipv4.tcp_rmem" = "4096 1048576 16777216";
      };
    };
  };

  # Samba is only for the hyprland host, so it's a separate option
  options.flake.modules.nixos.samba = lib.mkOption {
    type = lib.types.deferredModule;
    default = { ... }: {
      services.samba = {
        enable = true;
        settings = {
          global.security = "user";
          "pibackups" = {
            path = "/home/surya/Backup_Pi";
            browseable = "yes";
            "read only" = "no";
            "guest ok" = "no";
            "valid users" = "surya";
            "create mask" = "0664";
            "directory mask" = "0775";
          };
        };
        openFirewall = true;
      };
      services.samba-wsdd.enable = true;
    };
  };
}
