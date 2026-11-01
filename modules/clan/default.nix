{ inputs, ... }:
{
  imports = [
    inputs.clan-core.flakeModules.default
    ./inventory.nix
    ./machines.nix
  ];
}
