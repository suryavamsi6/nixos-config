# Host: NixOS Hyprland (x86_64-linux)
#
# Two things live here on purpose:
#
#   * `flake.modules.nixos.hyprlandHost` — the reusable host body: composition
#     list, host identity, Home Manager wiring. Clan evaluates this once the
#     migration flips (plans/clan-deploy-rs-migration.md §4).
#   * `flake.nixosConfigurations.nixos` — the transitional wrapper. It is
#     deleted in the flip step and exists only so the host keeps building from
#     an unchanged drvPath in the meantime.
{ config, inputs, lib, ... }:
{
  options.flake.modules.nixos.hyprlandHost = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { flakeModules, pkgs, ... }:
      {
      imports = with flakeModules; [
        inputs.nix-flatpak.nixosModules.nix-flatpak
        nixos.diskHealth # smartd + /var/lib/disk-health/health.json
        nixos.backups # nightly restic push to the pi
        nixos.resticClientVars # the restic-client var that push reads (§6)
        # Hardware
        nixos.hardwareHyprland
        nixos.nvidia
        nixos.gcb200
        nixos.openrgb
        nixos.coolercontrol
        nixos.apcupsd
        nixos.nutServer # re-export the apcupsd UPS as a NUT server for Nutify

        # Core system
        nixos.boot
        nixos.nixSettings
        nixos.users
        nixos.networking
        nixos.environment
        nixos.shell
        nixos.fonts
        nixos.audio
        # Import Windows' Bluetooth pairing keys so dual-boot devices stay paired.
        nixos.bluetoothDualboot
        nixos.greetd

        # Desktop
        nixos.hyprland
        nixos.serpantinum
        # Parallel SteamOS-style gamescope session, selectable at greetd.
        nixos.gamingMode

        # Packages
        nixos.gaming
        nixos.social
        nixos.system
        nixos.work

        # External modules
        inputs.chaotic.nixosModules.default

        nixos.locale

        # Host-specific config
        (
          {
            config,
            lib,
            pkgs,
            ...
          }:
          {
            # Allow this x86_64 desktop to build Raspberry Pi closures locally.
            boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
            boot.kernelPackages = pkgs.linuxPackages_cachyos-bore;

            # Hermes Desktop's bootstrap stages prebuilt generic-Linux binaries
            # (uv-managed CPython, Node toolchain pieces, browser helpers). NixOS
            # ships only a stub loader at /lib64/ld-linux-x86-64.so.2, which
            # refuses them with exit 127; nix-ld supplies a real loader plus the
            # shared libraries those prebuilt tools expect. Mirrors the
            # #raspberry-pi block (that one is aarch64).
            programs.nix-ld = {
              enable = true;
              libraries = with pkgs; [
                libffi
                sqlite
                ncurses
                readline
                expat
                libxcrypt
                # Hermes's cua-driver (computer-use helper, prebuilt) needs the
                # X11 stack at verification time.
                libx11
                xorg.libXext
                libxrandr
                xorg.libXrender
                libxi
                libxcb
                libxkbcommon
                wayland
              ];
            };

            # Generic-Linux prebuilt binaries (Hermes's staged CPython among
            # them) resolve the OpenSSL default CA file at /etc/ssl/cert.pem,
            # which NixOS does not ship. Point it at the system bundle so
            # certificate verification works out of the box for such tools.
            environment.etc."ssl/cert.pem".source = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";

            # The homelab's Caddy serves one HTTPS name, bifrost.home.arpa, signed
            # by its internal CA (MCP OAuth providers reject cleartext redirect
            # URIs). Trust that root here so the OAuth callback does not warn.
            # Copy it from the homelab first, then rebuild:
            #   ssh homelab.home.arpa \
            #     'sudo cat /var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt' \
            #     > modules/hosts/caddy-local-ca.crt
            # It is a public certificate; the CA key stays on the homelab. Until
            # the file exists this is a no-op, so the flake evaluates either way.
            security.pki.certificateFiles = lib.optionals (builtins.pathExists ./caddy-local-ca.crt) [
              ./caddy-local-ca.crt
            ];
            hardware.nvidia.package = lib.mkForce config.boot.kernelPackages.nvidiaPackages.new_feature;

            networking.hostName = "nixos";

            # ComfyUI and KoboldCpp use their own prebuilt CUDA artifacts; keeping
            # CUDA disabled in nixpkgs avoids compiling CUDA dependencies system-wide.
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

            system.nixos.tags = [ "cachyos" ];
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
            imports = with flakeModules; [
              homeManager.shell
              homeManager.hyprland
              homeManager.serpantinum
              homeManager.wallpapers
              homeManager.dev
              homeManager.work
              homeManager.gaming
              homeManager.comfyui
              homeManager.openbot
              homeManager.monocode
              homeManager.zeron
              homeManager.codex
              homeManager.chatgptDesktop
              homeManager.ghostex
              homeManager.herdr
              homeManager.orbitPi
              homeManager.piDesktop
              homeManager.pen
              homeManager.paper
              homeManager.synara
              homeManager.onepasswordMcp
              homeManager.factoryDesktopLinux
              homeManager.zenBrowser
              homeManager.t3codeNightly
            ];

            home.username = "surya";
            home.homeDirectory = "/home/surya";
            home.stateVersion = "24.11";
            programs.home-manager.enable = true;

            home.packages = [
              # homeManager.zenBrowser installs Zen: it wraps the package with the
              # Sine bootloader, so adding the plain twilight package here would
              # put a second, Sine-less zen-twilight on PATH.
              inputs.helium-browser.packages."x86_64-linux".helium
              pkgs.localsend
            ];
          };
        }
      ];
      };
  };
}
