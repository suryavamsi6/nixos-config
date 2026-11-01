# deploy-rs nodes: remote activation for the two servers.
#
#   deploy .#homelab       # x86_64 build on this workstation, then `nix copy`
#   deploy .#raspberry-pi  # aarch64 build ON the pi, never emulated here
#
# The desktops (`nixos`, `mango`) and the MacBook are absent on purpose: they are
# configured locally (`nh os switch`, `darwin-rebuild switch`), which is how they
# are actually used, and a remote deploy node for them would only add a way to
# lose a working desktop.
#
# What this gives us over `nixos-rebuild --target-host`: a magic rollback (the
# node must reach `deploy-rs-activate` again after activation or deploy-rs runs
# `nix-env --rollback` to the previous generation), per-node timeouts, and a
# `nix flake check` schema/activation check for free.
#
# See plans/clan-deploy-rs-migration.md §5.
{
  config,
  inputs,
  ...
}:
let
  drs = inputs.deploy-rs.lib;

  # Resolve the system from the configuration itself so the node cannot drift
  # from the host it deploys. `config.flake.nixosConfigurations` is the same
  # attribute whatever defines it (today the transitional wrappers in
  # `modules/hosts/*.nix`, later Clan's re-export).
  activationFor =
    name:
    let
      host = config.flake.nixosConfigurations.${name};
      system = host.pkgs.stdenv.hostPlatform.system;
    in
    drs.${system}.activate.nixos host;
in
{
  flake.deploy.nodes = {
    homelab = {
      hostname = "homelab.home.arpa";
      sshUser = "surya";
      sshOpts = [ "-T" ];
      profiles.system = {
        user = "root";
        path = activationFor "homelab";
      };

      # Defaults restated because they encode intent, not because they are needed.
      autoRollback = true;
      magicRollback = true;
      confirmTimeout = 60; # a busy homelab can take a while to come back
      activationTimeout = 600;
      fastConnection = false; # use the target's substituters before copying the whole closure
      remoteBuild = false; # i7 workstation builds; the laptop only runs `switch-to-configuration`
      # Activation runs `sudo -u root activate-rs`, and neither host has passwordless
      # sudo for its login user, so deploy must feed the password over stdin.
      # `deploy -i` prompts for it once per node.
      interactiveSudo = true;
    };

    raspberry-pi = {
      hostname = "pi.home.arpa";
      sshUser = "suryavamsi";
      sshOpts = [ "-T" ];
      profiles.system = {
        user = "root";
        path = activationFor "raspberry-pi";
      };

      autoRollback = true;
      magicRollback = true;
      confirmTimeout = 120; # the Pi is a Pi
      activationTimeout = 900;
      fastConnection = false;
      # Build aarch64 on the Pi itself. Emulating the whole system on x86_64 with
      # binfmt is slower than the network round trip and needs far more RAM.
      remoteBuild = true;
      interactiveSudo = true;
    };
  };

  # `deployChecks` validates `flake.deploy` against deploy-rs' interface.json and
  # asserts every profile carries its activation scripts. Runs as `nix flake check`.
  perSystem =
    { system, ... }: { checks = drs.${system}.deployChecks config.flake.deploy; };
}
