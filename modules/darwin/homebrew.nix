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
          upgrade = true;
          cleanup = "zap";
        };
        casks = [
          "1password"
          "citrix-workspace"
          "hermes-desktop"
          "tailscale-app"
          "zoom"
        ];
      };
    };
  };
}
