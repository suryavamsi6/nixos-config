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
          # Add macOS GUI apps here, e.g.:
          # "rectangle"
          # "alt-tab"
          # "firefox"
        ];
      };
    };
  };
}
