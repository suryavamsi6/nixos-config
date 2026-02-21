# Audio — PipeWire (NixOS)
{ lib, ... }:
{
  options.flake.modules.nixos.audio = lib.mkOption {
    type = lib.types.deferredModule;
    default = { ... }: {
      security.rtkit.enable = true;
      services.pipewire = {
        enable = true;
        alsa.enable = true;
        alsa.support32Bit = true;
        pulse.enable = true;
      };
    };
  };
}
