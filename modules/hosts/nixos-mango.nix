# Host: NixOS MangoWM scrolling-tags trial (x86_64-linux)
{ config, inputs, ... }:
{
  flake.nixosConfigurations.mango = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = {
      inherit inputs;
      system = "x86_64-linux";
    };
    modules = with config.flake.modules; [
      inputs.nix-flatpak.nixosModules.nix-flatpak
      # Same physical machine and hardware policy as #nixos.
      nixos.hardwareHyprland
      nixos.nvidia
      nixos.gcb200
      nixos.openrgb
      nixos.coolercontrol
      nixos.gridwatch

      # Core system
      nixos.boot
      nixos.nixSettings
      nixos.users
      nixos.networking
      nixos.environment
      nixos.shell
      nixos.fonts
      nixos.audio
      nixos.greetd

      # MangoWM and the shared Serpantinum desktop shell
      nixos.mango
      nixos.serpantinum
      nixos.gaming
      nixos.social
      nixos.system
      nixos.work
      nixos.hermesDesktop
      inputs.chaotic.nixosModules.default
      nixos.locale

      # Host-specific settings. The explicit #mango output is the only place
      # where Mango becomes the greetd default; #nixos remains Hyprland-first.
      (
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          tuigreet = "${pkgs.tuigreet}/bin/tuigreet";
          baseSessionsDir = "${config.services.displayManager.sessionData.desktops}";
          xSessions = "${baseSessionsDir}/share/xsessions";
          waylandSessions = "${baseSessionsDir}/share/wayland-sessions";
        in
        {
          boot.kernelPackages = pkgs.linuxPackages_cachyos-bore;
          hardware.nvidia.package = lib.mkForce pkgs.linuxPackages_cachyos-bore.nvidiaPackages.cachyos;

          networking.hostName = "mango";
          services.greetd.settings.default_session.command = lib.mkForce "${tuigreet} --remember --remember-session --sessions ${waylandSessions}:${xSessions} --time --cmd mango";
          nixpkgs.config.permittedInsecurePackages = [
            "libxml2-2.13.8"
            "libsoup-2.74.3"
          ];
          services.flatpak.enable = true;
          services.logind = {
            settings.Login.HandleLidSwitch = "ignore";
            settings.Login.HandleLidSwitchExternalPower = "ignore";
            settings.Login.HandleLidSwitchDocked = "ignore";
            settings.Login.KillUserProcesses = true;
          };

          system.nixos.tags = [ "mango" "cachyos" ];
          system.stateVersion = "24.11";
        }
      )

      # Home Manager
      inputs.home-manager.nixosModules.home-manager
      {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.backupFileExtension = "bak";
        home-manager.extraSpecialArgs = {
          inherit inputs;
          system = "x86_64-linux";
        };
        home-manager.users.surya = { pkgs, ... }: {
          imports = with config.flake.modules; [
            homeManager.shell
            homeManager.mango
            homeManager.serpantinum
            homeManager.wallpapers
            homeManager.dev
            homeManager.work
            homeManager.gaming
            homeManager.gridwatch
          ];

          home.username = "surya";
          home.homeDirectory = "/home/surya";
          home.stateVersion = "24.11";
          programs.home-manager.enable = true;

          home.packages = [
            inputs.zen-browser.packages."x86_64-linux".twilight
            inputs.helium-browser.packages."x86_64-linux".helium
            pkgs.chromium
            pkgs.localsend
          ];
        };
      }
    ];
  };
}
