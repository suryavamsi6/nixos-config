# Fleet facts: which machines exist, what class they are, how to reach them.
#
# Nothing here configures software. It is the answer to "what is in this fleet",
# which both Clan (`clan machines update`) and deploy-rs (`deploy .#…`) read —
# each from its own option, since Clan's `deploy.targetHost` and deploy-rs's
# `deploy.nodes.<h>.hostname` are unrelated schemas.
#
# The names must match the keys of `flake.clan.machines` in ./machines.nix: Clan
# derives one machine per inventory entry and names the resulting flake output
# after it (`flake.nixosConfigurations.<name>`).
{ ... }:
{
  flake.clan = {
    # The clan name shows up in `clan` CLI output; `domain` gives every machine a
    # `<hostname>.<domain>` name, which the homelab's Caddy already uses.
    meta = {
      name = "homelab";
      domain = "home.arpa";
    };

    inventory.machines = {
      # Servers: reachable over the LAN and deployed remotely.
      homelab = {
        machineClass = "nixos";
        tags = [
          "server"
          "x86_64"
        ];
        deploy = {
          targetHost = "homelab.home.arpa";
          buildHost = null; # workstation builds, then `nix copy`
        };
      };
      raspberry-pi = {
        machineClass = "nixos";
        tags = [
          "server"
          "aarch64"
        ];
        deploy = {
          targetHost = "pi.home.arpa";
          # Never emulate aarch64 on the x86_64 workstation: build on the Pi.
          buildHost = "pi.home.arpa";
        };
      };

      # Desktops stay local (`nh os switch`); they have no deploy target and are
      # deliberately absent from modules/clan/deploy.nix.
      nixos = {
        machineClass = "nixos";
        tags = [
          "desktop"
          "workstation"
          "x86_64"
        ];
        deploy.targetHost = null;
      };
      mango = {
        machineClass = "nixos";
        tags = [
          "desktop"
          "workstation"
          "x86_64"
        ];
        deploy.targetHost = null;
      };

      # Darwin: configures itself with `darwin-rebuild switch --flake .#macbook-air`.
      macbook-air = {
        machineClass = "darwin";
        tags = [
          "laptop"
          "aarch64"
        ];
        deploy.targetHost = null;
      };
    };
  };
}
