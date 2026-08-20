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
- Wallpapers: `inputs.shell-wallpapers` (`github:ilyamiro/shell-wallpapers`) → `~/Pictures/Wallpapers` via `modules/desktop/wallpapers.nix`. Super+W picker. Keep `pfp.png` local. HM files are symlinks; `qs_manager.sh` must `find -L` or the picker thumbs stay empty ("No wallpapers found"). Do not convert webp in-place in that folder.

## Bluetooth / audio

Intel Bluetooth (`btusb`, e.g. AX200/AX210). Paired: Sennheiser ACCENTUM Plus, MCHOSE K7 Ultra. MediaTek USB `0e8d:0616` is retired — unplug it.

- **Never** spawn `bluetoothctl` from bar/watchers (`scan on`, `--timeout`, poll loops). It registers AdvertisementMonitor and drops A2DP (`Host is down`).
- Query BlueZ with `busctl` (`bt_dbus.sh` / `bt_fetch.sh`). Device paths: `^${adapter}/dev_[^/]+$` (skip GATT children).
- Keep A2DP-only: no HFP/headset autoswitch, no `bluez5.roles` HFP/BAP. Citrix capture would flip profile and kill the headset. Use webcam mic for calls.
- Do not re-enable `bluetooth.autoswitch-to-headset-profile` without an explicit plan.

## Citrix

`modules/packages/work.nix`: wrap with `GDK_BACKEND=x11` (NVIDIA WebKit crash on Wayland).
`RememberUsername=true` via `overrideAttrs` on `AuthManConfig.xml`. **Never** store the MS username or password in the flake. Leave `SavePasswordMode` alone. Rebuild of this package is slow.

Entra/SAML login stays on the **embedded WebKitGTK dialog** — leave `AADSSOWithFido2AuthenticationEnabled` / `SharedAuthContextEnabled` / `FIDO2Enabled` at the vendor `false`. Setting them true routes login to `FIDO2AuthBrowser` over `ctxaadsso://`, and since Citrix only launches known browser names it opens a bare Firefox with no MS session or passkeys instead of a popup; the attempt then ends as `LogonResult_CancelledByUser` and Citrix never opens. (`InteractionNotAllowed` just before that is the normal failed silent-SSO probe, not the fault.) The `WEBKIT_DISABLE_COMPOSITING_MODE` / `WEBKIT_DISABLE_DMABUF_RENDERER` flags exist for that embedded dialog on NVIDIA; `firefox` on PATH is only for links opened from the store UI. `gnome-keyring` is Secret Service only — leave `gcr-ssh-agent` off (1Password).

**Stale Citrix daemons survive `nh os switch` and pin the old store path.** `systemd.services.citrix-reap-stale` (in `work.nix`) kills only `ServiceRecord` / `AuthManagerDaemon` / `PrimaryAuthManager` / `selfservice` / `ctxwebhelper` / `storebrowse` whose exe or cmdline is a *previous* `citrix-workspace` store path. It does **not** touch `wfica` or `icasessionmgr` (live session). The unit embeds the current package path, so it re-runs on switch only when Citrix itself changed. Manual check: compare `ps -eo pid,args` against `readlink -f /opt/Citrix/ICAClient`. Kill leftover PIDs by number — `pkill -f selfservice` matches your own shell. Signature if it still happens: nFactor hands over `m_StartUrl=.../nf/auth/startWebview.do`, no `PrimaryAuthManager` window maps, ~3s later `LogonResult_CancelledByUser` / "The user clicked cancel" with nothing clicked. Healthy: floating `PrimaryAuthManager` popup, then `CTokenCaches::AddAgSession`.

Zoom-inside-Citrix uses `zoomvdi-universal-plugin` **7.0.11.27050**, matching the VDI Zoom client (7.0.11). Version parity is mandatory: a 6.6.x plugin against a 7.0.x client loads, spawns the helper, fails the handshake and exits in ~1s loops with no error — looking exactly like a local crash. Check the client version in the VDI (Zoom → About) before debugging the host. Bump via `version`; the URL derives `shortVersion` from it, and builds are listed on Zoom's "VDI releases and downloads" KB. 7.0.x bundles Qt 6.8 (6.6.x was Qt 5.15) and needs `zstd`. `libZoomPlugin.so` is registered as Citrix `ZoomMedia.so`. Citrix execs the sibling `$plugin/zoom` inheriting wfica's `LD_LIBRARY_PATH` (no `libz`), so the helper must be self-sufficient: `patchelf --force-rpath --set-rpath` plugin+Qt+Nix libs onto `zoom`, `aomhost` and `crash_processor`. Also symlink Nix `.so`s into the plugin dir and `L+ /usr/lib/zoomvdi-universal-plugin`. `DT_RPATH` on the executable is *not* sufficient on its own — the loader prunes that list as it walks the dependency graph, so late lookups (`libxkbcommon`, `libz`, `libzstd`, `libEGL`) miss it and fall through to the system paths. `autoPatchelf` the bundled `Qt/lib`, `Qt/plugins` and `Qt/qml` too so every object carries its own runpath; the vendor Qt tree ships with none. Verify with `ldd`: `env -u LD_LIBRARY_PATH ldd $plugin/zoom` must report zero `not found`. Do not `buildFHSEnv` the helper. After a Citrix wrap change, `pkill icasessionmgr`. Do not bump the plugin past the VDI client version.

**`$plugin/zoom` must stay the unwrapped vendor ELF.** The plugin spawns it as its own sibling (no path is baked into the `.so`; the ini's `PATH` is only the child's `PATH`, and `BIN` is not read at all) with `--action=ZoomAVProcess --ipc_name=<GUID> --parent_pid=<wfica>`, the helper connects back to abstract socket `<GUID>zoomhdc`, and the plugin then authenticates the peer against the process it spawned — pid, `/proc/<pid>/cmdline` **and `/proc/<pid>/exe`**. Any exec wrapper (shell, `makeWrapper`, C shim) leaves `exe` pointing at the wrapper's target: the plugin closes the socket right after the handshake (15 `sendmsg`, then `recvmsg` returns 0) and the helper exits 0 in a ~2s retry loop that looks exactly like a local crash. So the wrapper's jobs are done without exec — libraries via `DT_RPATH`, environment and signals via a `DT_NEEDED` constructor (`libzoomvdifix.so`, `patchelf --add-needed`).

That constructor covers two things. wfica spawns the helper with SIGCHLD ignored, and an ignored disposition survives exec, so GLib's `g_spawn_sync` gets ECHILD probing `pactl --version`, Zoom logs "no pactl and pacmd found", and AV/VPT exit in ~1s loops (Settings never opens). Nothing outside the process can undo an inherited `SIG_IGN`. Reset **only** SIGCHLD — resetting SIGPIPE to `SIG_DFL` would turn a closed socket into a fatal signal. It also forces `QT_QPA_PLATFORM=xcb`: the bundle ships `libqxcb.so` but no usable wayland plugin, so an inherited `WAYLAND_DISPLAY` alone makes Qt abort. Check with `grep SigIgn /proc/<pid>/status` (bit 17 clear) and `readlink /proc/<pid>/exe`.

Note the helper does **not** inherit the session's Qt environment: wfica exports no `QT_PLUGIN_PATH`/`QML2_IMPORT_PATH`, so qt5ct/qt6ct contamination is not a real failure mode (it only appears when running `$plugin/zoom` from a login shell). The bundled `qt.conf` (`Prefix=./Qt`) resolves relative to the binary's own directory, which is another reason `zoom` must live in `$plugin` rather than behind a wrapper.

Do not add a tracing hatch to `$plugin/zoom`: `ptrace_scope=1` blocks attaching to a wfica child and any wrapper perturbs the identity checks above, so the hatch reproduces the failure it is meant to diagnose (even `strace -D`, which fixes only the pid). Trace by temporarily `--add-needed`-ing a logging shim instead. Running `$plugin/zoom` by hand falls back to the desktop `~/.zoom` dir and logs sqlcipher hmac failures — an artifact, not the bug; real runs use `~/.zoomvdi`.

`extraLibs` needs `alsa-lib` (Qt audio), `libxcursor`+`libxinerama` (dlopen'd by name from Qt xcb), `libxcomposite`+`libdrm` (SHAREOFFLOAD). Diagnose via `~/.zoomvdi/logs/zoom_stdout_stderr.log` and `coredumpctl` (Qt xcb aborts show as `createPlatformIntegration` SIGABRT). "VDI plugin not connected" inside Zoom with a healthy helper points at `VdiBridge::IsVersionMatch` — compare the packaged plugin version against the VDI-side Zoom version.

## Boot / disks

- NixOS on **nvme0n1** (Samsung 980 PRO): one **ext4** root (`label nixos`) + 2G `NIXBOOT` ESP. Windows 11 on **nvme1n1** (WD SN850X). Full wipe/reinstall steps: repo `README.md`.
- `/boot` is the **2G NixOS ESP** (`label NIXBOOT`), not the Windows ESP.
- Limine `extraConfig` is **prepended**. Put `default_entry: 3` first (1 Windows, 2 NixOS folder, 3 latest generation). A trailing `default_entry` is ignored.
- NIC: Realtek RTL8125 via out-of-tree `r8125` (`r8169` blacklisted). Ethernet `enp14s0`. Do not switch back to `r8169`.

## Secrets / safety

No MS/Citrix credentials, Wi-Fi PSKs, or OpenWeather keys in the flake. Weather key lives in `~/.config/hypr/openweather.env` (gitignored live file).
