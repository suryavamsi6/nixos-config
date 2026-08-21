# Module map

`flake.nix` → flake-parts → `modules/default.nix` (imports every subdirectory).
Each leaf file **declares** `options.flake.modules.*`. Hosts **select** which to use.

## Hosts (`modules/hosts/`)

| Flake attr | File | Desktop |
|---|---|---|
| `nixos` | `nixos-hyprland.nix` | Hyprland + Serpantinum |
| `plasma` | `nixos-gnome.nix` | GNOME |
| `macbook-air` | `darwin-macbook-air.nix` | nix-darwin |

`#nixos` HM user `surya` currently imports: `shell`, `hyprland`, `serpantinum`, `wallpapers`, `dev`, `work`.
`#plasma` uses the same `hardwareHyprland` module (this is one machine).

## Where to edit

| Change | File |
|---|---|
| Packages (system) | `modules/packages/system.nix` |
| Packages (dev / HM) | `modules/packages/dev.nix` |
| Citrix / Zoom / Zoom VDI plugin | `modules/packages/work.nix`, `zoomvdi-universal-plugin.nix` (gnome-keyring for CLStore; `gcr-ssh-agent` off) |
| PipeWire, BlueZ | `modules/audio/default.nix` (Intel `btusb`; A2DP-only) |
| Limine, Windows chainload | `modules/boot/default.nix` |
| NVIDIA | `modules/hardware/nvidia.nix` |
| GCB200 GPU-bracket LCD | `modules/hardware/gcb200.nix` (flake `github:suryavamsi6/gcb200-linux`) |
| Disks, kernel modules, r8125 | `modules/hardware/hyprland-hw.nix` (ext4; used by `#nixos` and `#plasma`; wipe guide in `README.md`) |
| NetworkManager / samba | `modules/networking/default.nix` (IPv6 off; BBR; Steam-oriented `tcp_rmem`; local `services.dnsmasq` cache in front of Pi-hole 192.168.0.105) |
| Fonts | `modules/fonts/default.nix` |
| Fish / kitty | `modules/shell/default.nix` |
| greetd | `modules/desktop/greetd.nix` |
| Bar / lock / launcher | `modules/desktop/serpantinum.nix` |
| Wallpapers (`ilyamiro/shell-wallpapers`) | `modules/desktop/wallpapers.nix` |
| Hyprland NixOS pkgs + HM Lua | `modules/hyprland/wm.nix` + `lua/` |
| New `#nixos` module | declare option, then add to `nixos-hyprland.nix` |

## `#nixos` NixOS imports (do not assume others)

`hardwareHyprland`, `nvidia`, `gcb200`, `boot`, `nixSettings`, `users`, `networking`, `samba`, `environment`, `shell`, `fonts`, `audio`, `greetd`, `hyprland`, `gaming`, `social`, `system`, chaotic, `locale`.
