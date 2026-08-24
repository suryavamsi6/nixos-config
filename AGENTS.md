# Repository Guidelines

## Project Overview

Nix flake configuration for:

- `#nixos`: primary NixOS host using Hyprland.
- `#plasma`: alternate Linux host using GNOME.
- `#macbook-air`: nix-darwin configuration for the MacBook Air.

The repository manages system modules, Home Manager user configuration, Hyprland Lua, Quickshell/Serpantinum desktop UI, hardware, networking, audio, and packaged work applications.

## Architecture & Data Flow

`flake.nix` uses flake-parts and imports `./modules`. `modules/default.nix` imports the module families. Leaf modules register deferred modules under `options.flake.modules.{nixos,homeManager,darwin}.*`; host files select those modules and compose NixOS, Home Manager, or nix-darwin systems.

Primary flow:

```text
flake inputs -> modules registry -> host selection -> system configuration
                                      -> Home Manager user files/services
                                      -> Hyprland Lua + Quickshell runtime
```

NixOS system configuration and Home Manager/user-runtime configuration are separate layers. A module definition is not enabled until the appropriate host imports it.

- Host wiring: `modules/hosts/`
- Hyprland: `modules/hyprland/wm.nix` and `modules/hyprland/lua/`
- Desktop shell: `modules/desktop/serpantinum.nix`
- Shell/user programs: `modules/shell/` and `modules/users/`
- Hardware/system services: `modules/hardware/`, `modules/audio/`, `modules/networking/`, `modules/boot/`
- Packages: `modules/packages/`

## Key Directories

- `modules/hosts/`: `#nixos`, `#plasma`, and `#macbook-air` composition.
- `modules/hyprland/lua/`: Lua configuration loaded by Hyprland 0.55+.
- `modules/desktop/`: Serpantinum/Quickshell, GNOME, greetd, and wallpapers.
- `modules/packages/`: custom derivations and application wrappers, including Citrix and Zoom VDI.
- `modules/hardware/`: GPU, disks, RGB, and device-specific configuration.
- `modules/shell/`: Fish, Kitty, Starship, and shell abbreviations.
- `.cursor/skills/` and `.agents/skills/`: detailed repository-specific operational guidance.

## Development Commands

Run commands from the repository root.

```bash
# Primary Linux host
nh os switch
# Equivalent explicit target
sudo nixos-rebuild switch --flake .#nixos

# GNOME host
sudo nixos-rebuild switch --flake .#plasma

# nix-darwin
nix run nix-darwin -- switch --flake .#macbook-air
darwin-rebuild switch --flake .#macbook-air

# After a Home Manager/Quickshell-only change, once switched
systemctl --user restart quickshell
```

Do not run a rebuild, switch, reboot, or destructive disk/install command unless explicitly requested. For reinstall work, match disks by `MODEL`, not `nvmeN`; the README's disk commands are hardware-specific.

## Code Conventions & Common Patterns

- Prefer existing module patterns: declare a deferred module in a leaf file, then wire it in the relevant host.
- Use Nix expressions and existing `lib`/`pkgs` conventions; avoid introducing a second module architecture.
- Hyprland uses `wayland.windowManager.hyprland.configType = "lua"`; edit `modules/hyprland/lua/*.lua`, not hyprlang.
- Hyprland Lua uses the `hl.*` API and explicit `require("vars")`/`extraLuaFiles` wiring. Runtime script paths normally resolve under `~/.config/hypr/scripts`.
- Serpantinum is patched at build time from the upstream flake input. Prefer `substituteInPlace` or focused Python patchers; do not maintain a full fork. Keep patch ordering intact, especially `patchTopBar` after clock substitutions.
- QML and shell launchers commonly use `Quickshell.execDetached` and watcher scripts. Preserve the existing watcher/cache and IPC flow rather than adding polling or parallel state paths.
- Shell scripts use `#!/usr/bin/env bash` with `set -euo pipefail` where failure must be explicit. When sourcing Serpantinum helpers, use a path based on `$(dirname "${BASH_SOURCE[0]}")`; `caching.sh` overwrites `SCRIPT_DIR`.
- Keep Bluetooth A2DP-only. Bar/watchers must query BlueZ through `busctl` helpers (`bt_dbus.sh`/`bt_fetch.sh`), never spawn `bluetoothctl`.
- Never put credentials, API keys, Wi-Fi PSKs, or work usernames in the flake. Weather secrets belong in the gitignored `~/.config/hypr/openweather.env`.
- Preserve package compatibility constraints, especially the pinned Zoom VDI version and Citrix/Quickshell wrapper behavior.

## Important Files

- `flake.nix`: inputs and system output entry point.
- `modules/default.nix`: module-family imports.
- `modules/hosts/nixos-hyprland.nix`: primary `#nixos` host and Home Manager wiring.
- `modules/hosts/nixos-gnome.nix`: `#plasma` host.
- `modules/hosts/darwin-macbook-air.nix`: `#macbook-air` host.
- `modules/hyprland/wm.nix`: Hyprland module and Lua file wiring.
- `modules/hyprland/lua/autostart.lua`: desktop process startup.
- `modules/hyprland/lua/binds.lua`: keybindings and script dispatch.
- `modules/desktop/serpantinum.nix`: Quickshell packaging, patches, scripts, and user service.
- `modules/packages/work.nix`: Citrix/work integration.
- `modules/packages/zoomvdi-universal-plugin.nix`: pinned Zoom VDI derivation.
- `README.md`: installation, rebuild, boot, and hardware workflows.

## Runtime/Tooling Preferences

Nix is the build/configuration system; use flakes and the repository's pinned inputs. The target systems are `x86_64-linux` and `aarch64-darwin`. User shell is Fish; terminal is Kitty. Quickshell is the configured desktop shell, wrapped with the required Qt6 QML import paths.

Development tools provided by the configuration include `nixfmt`, `treefmt`, `nixd`, `nix-init`, `git`, and `codex`. Follow existing Nix formatting and module conventions; do not add a new package manager or runtime without a concrete need.

## Testing & QA

There is no automated test suite, CI workflow, `devShell`, or flake `checks` output. QA is manual and should exercise the changed surface:

- Nix syntax: `nix-instantiate --parse path/to/file.nix` for focused parsing.
- Configuration changes: build/switch the affected host when authorized.
- Quickshell/Home Manager changes: switch, restart `quickshell`, and inspect the actual UI/runtime logs.
- Boot/hardware changes: use the README checklist (`lsblk -f`, `findmnt / /boot`, `df -hT /`, `lsusb`, `rfkill`) and verify the specific hardware behavior.

Do not claim a rebuild or runtime smoke test unless it was actually run. For changes to custom packages, preserve their explicit build hooks and test the resulting executable/library behavior rather than only parsing the Nix expression.
