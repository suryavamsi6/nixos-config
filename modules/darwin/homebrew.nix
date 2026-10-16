# Homebrew integration (Darwin)
{ lib, ... }:
{
  options.flake.modules.darwin.homebrew = lib.mkOption {
    type = lib.types.deferredModule;
    default = { ... }: {
      homebrew = {
        enable = true;
        onActivation = {
          autoUpdate = true;
          cleanup = "zap";
        };
        casks = [
          "1password"
          "citrix-workspace"
          "cursor"
          "grok-bot"
          "grok-build"
          "localsend"
          "tailscale-app"
          "thebrowsercompany-dia"
          "visual-studio-code"
          "zoom"
        ];
      };
    };
  };
}
