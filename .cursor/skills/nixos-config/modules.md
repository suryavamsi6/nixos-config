# Module map

`flake.nix` → flake-parts → `modules/default.nix` (imports every subdirectory).
Each leaf file **declares** `options.flake.modules.*`. Hosts **select** which to use.

## Hosts (`modules/hosts/`)

| Flake attr | File | Desktop |
|---|---|---|
| `nixos` | `nixos-hyprland.nix` | Hyprland + Serpantinum |
| `mango` | `nixos-mango.nix` | MangoWM + Serpantinum |
| `macbook-air` | `darwin-macbook-air.nix` | nix-darwin |

`#nixos` HM user `surya` currently imports: `shell`, `hyprland`, `serpantinum`, `wallpapers`, `dev`, `work`, `gaming`, `gridwatch`, `comfyui`, `hermesDesktop`, `capy`, `zenBrowser`. `#mango` also imports `capy`.

## Where to edit

| Change | File |
|---|---|
| Packages (system) | `modules/packages/system.nix` |
| Packages (dev / HM) | `modules/packages/dev.nix` (agent CLIs; OpenResearch/Epic-launcher wrappers) |
| Hermes Desktop (Electron shell for Hermes) | `modules/packages/hermes-desktop.nix` (pinned `install.sh` → `~/.hermes/hermes-agent`; electron-builder `--dir` → `linux-unpacked/{h,H}ermes` via FHS env runner; `#nixos` host carries the `programs.nix-ld` block) |
| Capy desktop | `modules/packages/capy.nix` (`homeManager.capy` on `#nixos` and `#mango`). Pinned `downloads.capy.ai` **tarball**, not the AppImage. Same-length `APPIMAGE` → `CAPY_BIN` patch in `app.asar`; do not set `APPIMAGE` |
| Citrix / Zoom / Zoom VDI plugin | `modules/packages/work.nix`, `citrix-adapter-wfica-shim.sh`, `zoomvdi-universal-plugin.nix` (gnome-keyring for CLStore; `gcr-ssh-agent` off) |
| PipeWire, BlueZ | `modules/audio/default.nix` (Intel `btusb`; A2DP-only) |
| Limine, Windows chainload | `modules/boot/default.nix` |
| NVIDIA | `modules/hardware/nvidia.nix` |
| GCB200 GPU-bracket LCD | `modules/hardware/gcb200.nix` (flake `github:suryavamsi6/gcb200-linux`) |
| OpenRGB (MSI Mystic Light / ARGB / RAM) | `modules/hardware/openrgb.nix` (`nixos.openrgb`); SDK `127.0.0.1:6742`. Do not add Artemis. |
| Disks, kernel modules, r8125 | `modules/hardware/hyprland-hw.nix` (ext4; used by `#nixos` and `#mango`; wipe guide in `README.md`) |
| NetworkManager | `modules/networking/default.nix` (IPv6 off; BBR; Steam-oriented `tcp_rmem`; local `services.dnsmasq` cache in front of Pi-hole 192.168.0.105) |
| Fonts | `modules/fonts/default.nix` |
| Fish / Ghostty | `modules/shell/default.nix` |
| greetd | `modules/desktop/greetd.nix` |
| Bar / lock / launcher | `modules/desktop/serpantinum.nix` |
| Wallpapers (`ilyamiro/shell-wallpapers`) | `modules/desktop/wallpapers.nix` |
| Hyprland NixOS pkgs + HM Lua | `modules/hyprland/wm.nix` + `lua/` |
| New `#nixos` module | declare option, then add to `nixos-hyprland.nix` |

## `#nixos` NixOS imports (do not assume others)

`hardwareHyprland`, `nvidia`, `gcb200`, `openrgb`, `boot`, `nixSettings`, `users`, `networking`, `environment`, `shell`, `fonts`, `audio`, `greetd`, `hyprland`, `gaming`, `social`, `system`, `work`, chaotic, `locale`.
