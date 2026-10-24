# Auto-imports all package modules
{ ... }:
{
  imports = [
    ./dev.nix
    ./work.nix
    ./gaming.nix
    ./social.nix
    ./system.nix
    ./comfyui.nix
    ./hermes-desktop.nix
    ./openbot.nix
    ./capy.nix
    ./claude-code-router.nix
    ./onepassword-mcp.nix
  ];
}
