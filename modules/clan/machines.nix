# Machine registry: machine name → the reusable host body it evaluates.
#
# A machine body is exactly what used to sit inside `nixosSystem { modules = …; }`
# in `modules/hosts/*.nix`. Those files now publish the same lists as deferred
# modules (`flake.modules.nixos.hyprlandHost`, …), so this file only has to map
# names onto them.
{ config, inputs, lib, ... }:
let
  m = config.flake.modules;

  # Clan's NixOS clanCore module turns three things on that this repo already
  # decides for itself. Each one changes the built system, so back them out per
  # machine and keep the pre-Clan drvPath baseline instead of accepting a silent
  # behaviour change:
  #
  #   enableRecommendedDefaults  sets `system.stateVersion` from a vars
  #                              generator, disables the HTML manual, nulls
  #                              `environment.ldso32`, and adds
  #                              nixos-facter/dnsutils/tcpdump/curl/jq/htop/git
  #                              to `environment.systemPackages`.
  #   settings.machine-id        pins `systemd.machine_id` in the kernel cmdline
  #                              and writes /etc/machine-id from a generated var.
  #   networking.hostId          clanCore/zfs.nix:10 sets it to the install ISO's
  #                              "8425e349" so ZFS pools import without
  #                              `forceImportRoot`. Only the SD-card profile
  #                              (nixos/modules/profiles/base.nix:71) sets that
  #                              value today — every other host leaves hostId
  #                              null — and the value still adds a `gen-hostid`
  #                              input to the initrd
  #                              (nixos/modules/tasks/network-interfaces.nix:1808).
  #
  # `platform` replaces the `system` argument the old `lib.nixosSystem` call
  # passed: Clan constructs machines with `nixosSystem { modules = …; }` only, so
  # a host whose body does not set `nixpkgs.hostPlatform` would otherwise fail
  # with "Neither nixpkgs.hostPlatform nor the legacy option nixpkgs.system has
  # been set". `nixpkgs.system` is used rather than `nixpkgs.hostPlatform` because
  # that is exactly what `lib.nixosSystem`'s `system` argument set (a `mkDefault`
  # on the legacy option), so the derived pkgs — and therefore the drvPath — stay
  # identical.
  nixosMachine =
    {
      body,
      platform ? null,
      # `null` matches every host that never set a hostId; the SD-card image is
      # the one host whose baseline value comes from nixos/modules/profiles/base.nix.
      hostId ? null,
    }:
    {
      imports = [ body ];
    }
    // {
      clan.core.enableRecommendedDefaults = false;
      clan.core.settings.machine-id.enable = false;
      networking.hostId = lib.mkForce hostId;
    }
    // lib.optionalAttrs (platform != null) {
      nixpkgs.system = platform;
    };
in
{
  flake.clan = {
    # Clan evaluates machine bodies with `specialArgs = { inherit clan-core; }`
    # plus whatever is declared here — NOT with the flake's own `config`. Our
    # deferred modules take `{ inputs, ... }` (e.g. modules/hardware/gcb200.nix:7,
    # modules/desktop/zen.nix:51), so `inputs` has to be forwarded explicitly or
    # evaluation recurses; `flakeModules` is the registry handle the host bodies
    # consume via `with flakeModules;`.
    specialArgs = {
      flakeModules = m;
      inherit inputs;
    };

    machines = {
      # The machine name IS the flake output name: Clan builds
      # `flake.nixosConfigurations.<name>` / `flake.darwinConfigurations.<name>`
      # from it. That is why the Step 1 probes carried a `-clan` suffix while the
      # wrappers still existed.
      homelab = nixosMachine { body = m.nixos.homelab; };
      raspberry-pi = nixosMachine {
        body = m.nixos.raspberryPi;
        platform = "aarch64-linux";
        hostId = "8425e349"; # nixos/modules/profiles/base.nix:71, kept verbatim
      };
      nixos = nixosMachine { body = m.nixos.hyprlandHost; };
      mango = nixosMachine { body = m.nixos.mangoHost; };

      # Darwin: clanCore is the same module set over nix-darwin
      # (nixosModules/flake-module.nix:41 `flake.darwinModules.clanCore = clanCore`),
      # so `enableRecommendedDefaults` applies here too — it adds
      # dnsutils/tcpdump/curl/jq/htop/gitMinimal to systemPackages and turns the
      # manual off. `machine-id` and `zfs.nix` are NixOS-only, and the darwin
      # body sets its own `nixpkgs.hostPlatform = "aarch64-darwin"`.
      macbook-air = {
        imports = [ m.darwin.macbookAir ];
        clan.core.enableRecommendedDefaults = false;
      };
    };
  };

  # `machineClass` is an *inventory* fact, not a machine-module option, so the
  # darwin probe declares it here. (Clan derives `inventory.machines.<n>` from
  # `flake.clan.machines.<n>` with defaults; this adds the one non-default.)
  flake.clan.inventory.machines.macbook-air.machineClass = "darwin";
}
