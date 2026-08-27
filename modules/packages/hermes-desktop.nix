# Always-on Hermes integration for the LAN desktop worker.
{ lib, ... }:
{
  options.flake.modules.nixos.hermesDesktop = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { pkgs, ... }:
      {
        environment.systemPackages = [
          pkgs.ethtool
          pkgs.wakeonlan
        ];

        networking.interfaces.enp14s0.wakeOnLan = {
          enable = true;
          policy = [ "magic" ];
        };

        services.openssh = {
          enable = true;
          settings = {
            PasswordAuthentication = false;
            KbdInteractiveAuthentication = false;
            PermitRootLogin = "no";
          };
        };

        # The desktop has no public interface; allow these services only on
        # the wired LAN. Router and SSH credentials still gate access.
        services.ollama = {
          enable = true;
          host = "0.0.0.0";
        };
        networking.firewall.interfaces.enp14s0.allowedTCPPorts = [
          22
          11434
        ];

        users.users.surya.openssh.authorizedKeys.keys = [
          # The local-terminal profile uses this key by default. Keep it
          # separate from the dedicated backend key above.
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEN6DPzf+EdlzF5CzsO+Mw4tOKIyVzF8j77oUD6MLRO/ hermes-pi-to-nix@20260826"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICV+g/pqn4uIXqrOUV8Efi1wdD39OmjzPyKrjVrztCj6 hermes-pi-to-nixos"
        ];
      };
  };
}
