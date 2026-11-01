{ inputs, ... }:
{
  imports = [
    inputs.clan-core.flakeModules.default
    ./inventory.nix
    ./machines.nix
    ./vars.nix
    ./secrets.nix # per-machine generators (flake.modules.nixos.*Vars)
    ./deploy.nix
  ];
}
