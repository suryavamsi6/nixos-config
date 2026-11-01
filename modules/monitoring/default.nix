# Auto-imports all monitoring modules
{ ... }:
{
  imports = [
    ./disk-health.nix
    ./backups.nix
    ./nut-server.nix
  ];
}
