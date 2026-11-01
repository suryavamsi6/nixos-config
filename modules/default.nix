# Auto-imports all subdirectory modules
{ ... }:
{
  imports = [
    ./hosts
    ./hardware
    ./shell
    ./hyprland
    ./desktop
    ./mangowm
    ./darwin
    ./networking
    ./nix-settings
    ./users
    ./packages
    ./fonts
    ./audio
    ./boot
    ./environment
    ./locale
    ./monitoring
    # Fleet-level wiring last: it consumes the registry above, so its machine
    # bodies can reference every deferred module without an import cycle.
    ./clan
  ];
}
