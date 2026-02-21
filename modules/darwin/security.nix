# macOS security settings (Darwin)
{ lib, ... }:
{
  options.flake.modules.darwin.security = lib.mkOption {
    type = lib.types.deferredModule;
    default = { ... }: {
      # Enable Touch ID for sudo authentication
      security.pam.services.sudo_local.touchIdAuth = true;
    };
  };
}
