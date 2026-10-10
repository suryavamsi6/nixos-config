# SteamOS-style "Gaming Mode" session (NixOS)
#
# A gamescope session that behaves like SteamOS Game Mode: gamescope owns the
# display and runs Steam's Deck UI on top of it. It is installed as a selectable
# Wayland session next to Hyprland, so `#nixos` gains a parallel gaming
# environment without changing the default desktop.
#
# This replaces the bare `steam.desktop` that nixpkgs generates for
# `programs.steam.gamescopeSession`, so the greeter shows one clearly named
# entry instead of a second, unconfigured one.
{ lib, ... }:
{
  options.flake.modules.nixos.gamingMode = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { config, pkgs, ... }:
      let
        # The MAG 341C is the only connected output. NVIDIA drivers expose the
        # same physical port as either name, and Hyprland's Lua monitor profile
        # pins the same mode on both.
        connectorPreference = "HDMI-A-2,HDMI-A-1";
        outputWidth = 3440;
        outputHeight = 1440;

        # `programs.gamescope` is enabled for `enableWsi` (the Vulkan layer) and
        # its udev/kernel defaults. Its own `args`/`env` options do not reach
        # this session because the session passes its flags explicitly below.
        gamescope = "${pkgs.gamescope}/bin/gamescope";
        steam = "${config.programs.steam.package}/bin/steam";

        # Only coreutils (`id`) is a runtime input: greetd hands sessions a
        # minimal PATH, and nothing here spawns gamescope's own overlay.
        sessionScript = pkgs.writeShellApplication {
          name = "steam-gamemode";
          runtimeInputs = [ pkgs.coreutils ];
          text = ''
            # SteamOS session identity. Portal backends, theme selection and
            # client-side session detection key off these.
            export XDG_CURRENT_DESKTOP=gamescope
            export XDG_SESSION_DESKTOP=gamescope

            # greetd hands sessions the minimal PATH from greetd.service
            # (coreutils/findutils/gnugrep/gnused/systemd) and there is no
            # /etc/environment to extend it. Steam launch options resolve
            # helpers by name (`gamemoderun %command%`, `env -u TZ ...`), so
            # restore the standard NixOS session PATH before handover.
            username="$(id -un)"
            export PATH="/run/wrappers/bin:/run/current-system/sw/bin:/etc/profiles/per-user/$username/bin:/nix/var/nix/profiles/default/bin:$HOME/.nix-profile/bin:/nix/profile/bin:$HOME/.local/bin:$PATH"

            # MangoHud is the only overlay here. It stays enabled for games
            # (see modules/packages/gaming.nix) because the Vulkan layer's
            # `enable_environment` requires MANGOHUD=1, and that is what makes
            # the per-game MANGOHUD_CONFIGFILE launch options (and their fps
            # caps) work, exactly as on Hyprland.
            #
            # `--mangoapp` is deliberately NOT passed: it adds a second,
            # gamescope-rendered overlay on top of MangoHud's. gamescope still
            # exports STEAM_USE_MANGOAPP for Steam (`setenv` with overwrite=0
            # in main.cpp), so if Steam ever brings an overlay back on its own,
            # `export STEAM_USE_MANGOAPP=` before exec is the lever.
            #
            # `--steam` makes gamescope export the STEAM_GAMESCOPE_* capability
            # variables (VRR, tearing, HDR, NIS, WSI, multiple XWaylands) that
            # Steam's Deck UI reads, so they are deliberately not set here:
            # gamescope reports what this display and driver actually support.
            #
            # `--hdr-enabled` matches the Hyprland/MangoWM monitor profile, which
            # runs the MAG 341C in HDR (`cm = "hdr"`, `bitdepth = 10`). Without
            # it the compositor is SDR while games whose launch options set
            # `PROTON_ENABLE_HDR=1` (Onimusha) ask for an HDR swapchain — a
            # mismatch the desktop never has, and the leading suspect for that
            # game's freeze.
            # gamescope owns the display, so its diagnostics are the only window
            # into session-level failures and greetd discards them.
            gamescope_log="''${XDG_RUNTIME_DIR:-/tmp}/gamescope.log"

            exec >>"$gamescope_log" 2>&1 \
              ${gamescope} \
              --steam \
              --hdr-enabled \
              --adaptive-sync \
              --prefer-output=${connectorPreference} \
              -W ${toString outputWidth} -H ${toString outputHeight} \
              -- \
              ${steam} -gamepadui -pipewire-dmabuf
          '';
        };

        sessionPackage =
          (pkgs.writeTextDir "share/wayland-sessions/gaming-mode.desktop" ''
            [Desktop Entry]
            Name=Gaming Mode (Steam)
            Comment=SteamOS-style gamescope session
            Exec=${sessionScript}/bin/steam-gamemode
            Type=Application
          '').overrideAttrs
            (_: {
              passthru.providedSessions = [ "gaming-mode" ];
            });
      in
      {
        # This module owns the Game Mode entry. The shared gaming module still
        # enables nixpkgs' variant for the other hosts, so force it off here to
        # avoid a duplicate, unconfigured "Steam" session in the greeter.
        programs.steam.gamescopeSession.enable = lib.mkForce false;

        programs.gamescope = {
          enable = true;
          enableWsi = true;
        };

        services.displayManager.sessionPackages = [ sessionPackage ];
      };
  };
}
