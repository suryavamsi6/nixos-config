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
          # Carry the login user in the address. `clan_cli`'s `_parse_ssh_uri`
          # defaults a bare host to `root@`, and this host sets
          # `PermitRootLogin = "no"` (nixos-homelab.nix), so a bare hostname can
          # only ever fail with `Permission denied (publickey)`. With a user,
          # `Remote.become_root` runs the privileged half through a sudo askpass
          # prompt instead. Matches deploy-rs (`sshUser = "surya"` in deploy.nix).
          targetHost = "surya@homelab.home.arpa";
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
          # IP, not `pi.home.arpa`: that name resolves only through the Pi's own
          # AdGuard rewrite, so resolving it would depend on the generation being
          # deployed (deploy.nix documents the same for its `hostname`). Fresh
          # installs have no DNS at all.
          targetHost = "suryavamsi@192.168.0.105";
          # Never emulate aarch64 on the x86_64 workstation: build on the Pi.
          buildHost = "suryavamsi@192.168.0.105";
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
