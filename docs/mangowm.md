# MangoWM scrolling-tags trial

The experimental host is `#mango`. The existing `#nixos` host remains the Hyprland-first system and is not replaced by this trial.

## Build without switching

From the repository root:

```bash
nix build --no-link .#nixosConfigurations.mango.config.system.build.toplevel
```

A Mango Home Manager session also exports `NH_OS_FLAKE` to this host, so plain `nh os switch` targets `#mango` while Mango is active. Use an explicit `...#nixos` installable when rolling back.

## Login/session behavior

The Mango output uses `mango` as its explicit greetd default and installs a selectable MangoWM Wayland session through `programs.mango`. The normal `#nixos` output continues to use:

```text
start-hyprland
```

At greetd, keep the remembered Hyprland session on `#nixos`; on the experimental output choose MangoWM from the session list if the remembered session is not already Mango.

## First workflow

- `Ctrl+1` through `Ctrl+9` view tags 1–9; `Alt+1` through `Alt+9` move the focused client to tags 1–9.
- There are nine tags total; tag 10 and the `0` tag bindings have been removed.
- `Super+Shift+1…9` toggles the focused window's membership in each tag. Press multiple combinations—for example, `Super+Shift+1` then `Super+Shift+3`—to place it on tags 1 and 3.
- `Alt+Left/Right/Up/Down` focuses; `Super+Shift` plus a direction exchanges clients.
- Mango uses the `dwindle` layout on every tag; the tag rules explicitly pin tags 1–9 to it.
- `Super+R` hot-reloads Mango config. `Super+M` exits Mango. `Super+C`, `Alt+Q`, or `Alt+F4` closes the focused app.
- `Super+Tab` cycles focus; `Super+Shift+Tab` toggles Mango's overview. `Super+L` or the power key invokes Serpantinum's lock screen.
- `Alt+Space` opens Serpantinum's launcher; `Alt+Return` opens Ghostty. `Alt+F` toggles fullscreen and `Alt+\\` toggles floating.
- `Super+1…9` switch tags 1–9 directly; `Ctrl+number` remains an alias, `Alt+number` moves the focused client, and `Super+Shift+number` toggles multi-tag membership.
- `Super+Space` or `Alt+Space` opens the Serpantinum launcher. `Super+Q`/`Super+Return` opens Ghostty, `Super+E` opens Superfile, `Super+B` opens Zen, and `Super+P` opens the color picker.

The Mango package is pinned to the upstream `wl-only` commit `f637c0c81166a801861fa0c1d49c8f3c31a3fc84` because Scenefx cannot perform the output color transforms required for HDR. The monitor rules request HDR10 with Vulkan and `hdr_force:1` for the MAG 341C OLED. VRR remains disabled globally and is enabled only for true-fullscreen Steam App/GameScope windows with `vrr_only_fullscreen:1`; HDR/VRR changes require a fresh Mango login.

## Ported desktop services

Mango uses the existing Serpantinum Quickshell shell for the top bar, launcher, notifications, clipboard, wallpaper controls, lock screen, UPS, Bluetooth, network, volume, calendar, and focus-time panels. Noctalia is not part of this host.

Mango status/control integration should use `mmsg` rather than Hyprland commands:

```bash
mmsg get all-tags
mmsg get all-monitors
mmsg watch all-tags
mmsg dispatch reload_config
```

## Gaming

The shared gaming module remains the source of truth for Steam, Gamescope, GameMode, MangoHud, and Proton. Mango's `mango-idle.service` is stopped by GameMode alongside the existing Hyprland idle unit and restored when the game exits. Validate XWayland titles, Gamescope, NVIDIA DRM modeset, VRR/fullscreen, capture portals, controllers, audio, and Bluetooth before treating the trial as gaming-ready.

## Rollback

- If Mango fails at login, use the greetd session selector to return to the available Hyprland session when running the normal `#nixos` generation.
- From the boot menu, select the last known-good NixOS generation.
- To stop using the trial, build or switch back to `.#nixos`; do not remove the Mango files while diagnosing it.
- Collect diagnostics before changing anything:

```bash
journalctl -b -u greetd
journalctl --user -b -u mango-idle.service -u mango-polkit-agent.service
journalctl --user -b -u serpantinum.service
mmsg get version
mmsg get all-monitors
mmsg get all-tags
```

Known first-trial limitations: semantic labels are not automatic app routing; Serpantinum controls that depended on Hyprland dispatch must be audited individually; the current pinned nixpkgs Home Manager has no native Mango module, so this repository owns the small config/session bridge.
