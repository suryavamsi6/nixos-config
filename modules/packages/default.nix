# Auto-imports all package modules
{ ... }:
{
  imports = [
    ./factory-desktop-linux.nix
    ./dev.nix
    ./work.nix
    ./gaming.nix
    ./social.nix
    ./system.nix
    ./comfyui.nix
    ./hermes-desktop.nix
    ./openbot.nix
    ./monocode.nix
    ./zeron.nix
    ./capy.nix
    ./claude-code-router.nix
    ./codex.nix
    ./chatgpt-desktop.nix
    ./onepassword-mcp.nix
    ./cliproxyapi.nix
    ./ghostex.nix
    ./herdr.nix
    ./orbit-pi.nix
    ./pi-desktop.nix
    ./pen.nix
    ./paper.nix
    ./synara.nix
    ./t3code-nightly.nix
  ];
}
