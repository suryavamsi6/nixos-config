# Auto-imports all service modules.
#
# These are host-agnostic `flake.modules.nixos.<name>` definitions extracted out
# of modules/hosts/nixos-homelab.nix (plans/clan-deploy-rs-migration.md §7), so
# another machine — the pi, or a future host — can import them by name.
{ ... }:
{
  imports = [
    ./netdata.nix
    ./gatus.nix
    ./searxng.nix
    ./homepage.nix
    ./grok-oauth-proxy.nix
    ./caddy.nix
    ./openbot.nix
    ./reactive-resume.nix
    ./nutify.nix
    ./qdrant.nix
  ];
}
