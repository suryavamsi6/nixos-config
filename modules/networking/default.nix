# Networking — NetworkManager (NixOS)
{ lib, ... }:
{
  options.flake.modules.nixos.networking = lib.mkOption {
    type = lib.types.deferredModule;
    default = { ... }: {
      networking.networkmanager = {
        enable = true;
        wifi.powersave = false;
        # enableIPv6=false is not enough: NM still sets
        # net.ipv6.conf.enp14s0.disable_ipv6=0, Steam's IPv6 probe
        # times out, then "downgrading to ipv4-only" (~2–30 Mbps).
        connectionConfig."ipv6.method" = "disabled";
        # Dedicated services.dnsmasq owns :53. NM must not spawn its
        # plugin or write DHCP DNS (the LAN Pi-hole) into resolv.conf.
        dns = "none";
      };
      networking.nameservers = [ "127.0.0.1" ];
      # Stub on 127.0.0.53 would steal queries from dnsmasq.
      services.resolved.enable = false;
      # Steam looks up CDN names on every chunk. Talking to the Pi-hole
      # (192.168.0.105) directly saturates it, then nix fails with
      # "Could not resolve host: nix-community.cachix.org". Cache here,
      # forward misses to Pi-hole so ads still get blocked.
      # Do not also set NM dns=dnsmasq — two listeners on :53.
      services.dnsmasq = {
        enable = true;
        settings = {
          listen-address = [ "127.0.0.1" ];
          bind-interfaces = true;
          no-resolv = true;
          cache-size = 10000;
          min-cache-ttl = 3600;
          server = [ "192.168.0.105" ];
          # Cap in-flight forwards so a cold Steam cache cannot knock
          # the Pi over (default 150). Local hits do not count.
          dns-forward-max = 32;
          # IPv6 is disabled; AAAA answers make glibc/curl prefer
          # unreachable v6 and can surface as resolve failures.
          filter-AAAA = true;
        };
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

}
