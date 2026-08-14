---
name: nixos-config
description: >-
  Edit this flake-parts NixOS/Home Manager/nix-darwin repo (suryavamsi6/nixos-config).
  Use when changing .nix modules, Hyprland Lua, Serpantinum/Quickshell, Limine,
  PipeWire/Bluetooth, Citrix, or when rebuilding the #nixos host.
paths:
  - "**/*.nix"
  - "modules/hyprland/lua/**"
  - "modules/desktop/serpantinum.nix"
---

# This flake

Primary Linux host is `nixosConfigurations.nixos` (hostname `nixos`, user `surya`).
GNOME alt is `#plasma`. Darwin is `#macbook-air` (user `suryavamsi`). Default work
target is **Hyprland `#nixos`** unless the user says otherwise.

Read [modules.md](modules.md) before adding a new module or guessing import paths.

## Workflow

1. Change the `options.flake.modules.{nixos,homeManager,darwin}.*` deferredModule, then wire it in the host file if it is new.
2. Do not `nixos-rebuild` / `nh os switch` / reboot unless the user asks. Tell them to run `nh os switch` from this repo.
3. Do not commit unless asked. Do not write git config. Author if committing: `Surya Vamsi <d.suryavamsi@gmail.com>`.
4. After HM/Quickshell-only changes, `systemctl --user restart quickshell` is enough once switched.

## Module pattern

```nix
options.flake.modules.homeManager.example = lib.mkOption {
  type = lib.types.deferredModule;
  default = { pkgs, ... }: { /* HM options */ };
};
```

Import only from the host file (`modules/hosts/nixos-hyprland.nix` for `#nixos`) via
`with config.flake.modules`. Defining a module does **not** enable it.

Dead (defined, not imported by `#nixos`): `ags`, `swaync`, `hyprlauncher`, `hyprpaper`, `gtkTheme`.
Do not revive them unless asked. Desktop shell is **Serpantinum** (Quickshell).

## Hyprland

- `wayland.windowManager.hyprland.configType = "lua"` (0.55+). Edit `modules/hyprland/lua/*.lua`, not hyprlang.
- Dispatchers are Lua: `hyprctl dispatch 'hl.dsp.dpms("off")'`, not `dispatch dpms off`.
- Monitor: MAG 341C OLED `HDMI-A-2` `3440x1440@175` HDR in `lua/monitors.lua`.
- DM: greetd/tuigreet. Shell: Fish. Terminal: kitty. Browser package: zen-twilight.

## Serpantinum

`modules/desktop/serpantinum.nix` copies `inputs.serpantinum` (flake=false) into
`xdg.configFile."hypr/scripts"` and patches at build time.

- Prefer `substituteInPlace` / Python patchers in that Nix file. Do not maintain a full fork.
- `caching.sh` **overwrites `SCRIPT_DIR`**. Source helpers with `"$(dirname "${BASH_SOURCE[0]}")/..."`, never `$SCRIPT_DIR`.
- `patchTopBar` must still run after the clock `HH:mm` substitute, or the bar loses Wi-Fi/BT pills.
- Python inside Nix strings: keep indent uniform or use `textwrap.dedent`. A less-indented `r"""` causes `IndentationError` at build.
- Live files after switch: `~/.config/hypr/scripts/quickshell/`.

## Bluetooth / audio

MediaTek USB BT `0e8d:0616` (`btusb`). Paired: Sennheiser ACCENTUM Plus, MCHOSE K7 Ultra.

- **Never** spawn `bluetoothctl` from bar/watchers (`scan on`, `--timeout`, poll loops). It registers AdvertisementMonitor and drops A2DP (`Host is down`).
- Query BlueZ with `busctl` (`bt_dbus.sh` / `bt_fetch.sh`). Device paths: `^${adapter}/dev_[^/]+$` (skip GATT children).
- Keep A2DP-only: no HFP/headset autoswitch, no `bluez5.roles` HFP/BAP. Citrix capture would flip profile and kill the headset. Use webcam mic for calls.
- Do not re-enable `bluetooth.autoswitch-to-headset-profile` without an explicit plan.

## Citrix

`modules/packages/work.nix`: wrap with `GDK_BACKEND=x11` (NVIDIA WebKit crash on Wayland).
`RememberUsername=true` via `overrideAttrs` on `AuthManConfig.xml`. **Never** store the MS username or password in the flake. Leave `SavePasswordMode` alone. Rebuild of this package is slow.

Zoom-inside-Citrix uses `zoomvdi-universal-plugin` 6.6.11 (must match VDI Zoom). `libZoomPlugin.so` is registered as Citrix `ZoomMedia.so`. Citrix execs the sibling `$plugin/zoom` inheriting wfica's `LD_LIBRARY_PATH` (no `libz`); that file must be a `makeWrapper` that `--set`s plugin+Qt+Nix libs. Also symlink Nix `.so`s into the plugin dir and `L+ /usr/lib/zoomvdi-universal-plugin`. Do not `buildFHSEnv` the helper. After a Citrix wrap change, `pkill icasessionmgr`. Do not bump the plugin past the VDI client version.

## Boot / disks

- NixOS on `nvme1n1` (btrfs `@ @home @nix @log @swap`). Windows 11 on `nvme0n1`.
- `/boot` is the **2G NixOS ESP** (`label NIXBOOT`), not the Windows ESP. README dual-boot section that says “shared Windows EFI” is stale.
- Limine `extraConfig` is **prepended**. Put `default_entry: 3` first (1 Windows, 2 NixOS folder, 3 latest generation). A trailing `default_entry` is ignored.
- NIC: Realtek RTL8125 via out-of-tree `r8125` (`r8169` blacklisted). Ethernet `enp14s0`. Do not switch back to `r8169`.

## Secrets / safety

No MS/Citrix credentials, Wi-Fi PSKs, or OpenWeather keys in the flake. Weather key lives in `~/.config/hypr/openweather.env` (gitignored live file).
