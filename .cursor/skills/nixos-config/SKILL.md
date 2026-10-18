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

Primary Linux host is `nixosConfigurations.nixos` (hostname `nixos`, user `surya`). Mango is the optional `#mango` trial host. Darwin is `#macbook-air` (user `suryavamsi`). Default work
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

Dead desktop modules were removed (AGS, SwayNC, hyprlauncher, hyprpaper, gtkTheme). Do not revive them unless asked. Desktop shell is **Serpantinum** (Quickshell).

## Hyprland

- `wayland.windowManager.hyprland.configType = "lua"` (0.55+). Edit `modules/hyprland/lua/*.lua`, not hyprlang.
- Dispatchers are Lua: `hyprctl dispatch 'hl.dsp.dpms("off")'`, not `dispatch dpms off`.
- Monitor: MAG 341C OLED `HDMI-A-2` `3440x1440@175` HDR in `lua/monitors.lua`.
- Workspace overview: hyprexpose (standalone overlay, not a C++ plugin). Super+Tab sits next to clipboard (Super+D) on the Node 100 custom row; also `XF86LaunchA`. Daemon: `hyprexpose --allow-mouse`, toggle `pkill -USR1 -x hyprexpose`. Esc closes. hymission does not compile against locked Hyprland git (CWindow members moved onto presentation/state). Do not mix hyprpm.
- DM: greetd/tuigreet. Shell: Fish. Terminal: Ghostty. Browsers on `#nixos`: zen-twilight (Super+B) and Helium (`inputs.helium-browser`). Do not add Floorp or other browsers. `pkgs.firefox` stays only on the Citrix wrapper PATH for store-UI links, not as a desktop browser.

## Serpantinum

`modules/desktop/serpantinum.nix` copies `inputs.serpantinum` (flake=false) into
`xdg.configFile."hypr/scripts"` and patches at build time.

- Prefer `substituteInPlace` / Python patchers in that Nix file. Do not maintain a full fork.
- `caching.sh` **overwrites `SCRIPT_DIR`**. Source helpers with `"$(dirname "${BASH_SOURCE[0]}")/..."`, never `$SCRIPT_DIR`.
- `patchTopBar` must still run after the clock `h:mm AP` substitute, or the bar loses Wi-Fi/BT pills. Keep the bar on 12-hour (`h:mm AP`); calendar big clock is `h:mm`.
- Python inside Nix strings: keep indent uniform or use `textwrap.dedent`. A less-indented `r"""` causes `IndentationError` at build.
- Live files after switch: `~/.config/hypr/scripts/quickshell/`.
- Battery popup reads laptop `BAT*` then UPower UPS (APC Back-UPS RS 1500G-IN on this box; it is not under `/sys/class/power_supply`). Hide power-profiles and brightness when PPD/backlight are absent. Do not add `power-profiles-daemon` just to fill that dock.
- Wallpapers: `inputs.shell-wallpapers` (`github:ilyamiro/shell-wallpapers`) → `~/Pictures/Wallpapers` via `modules/desktop/wallpapers.nix`. Super+W picker. Keep `pfp.png` local. HM files are symlinks; `qs_manager.sh` must `find -L` or the picker thumbs stay empty ("No wallpapers found"). Do not convert webp in-place in that folder.

## Bluetooth / audio

MediaTek MT7922 combo (`btusb`; USB id `0e8d:0616` is the card, not a dongle — do not unplug). Paired: Sennheiser ACCENTUM Plus, MCHOSE K7 Ultra.

- **Never** spawn `bluetoothctl` from bar/watchers (`scan on`, `--timeout`, poll loops). It registers AdvertisementMonitor and drops A2DP (`Host is down`).
- Query BlueZ with `busctl` (`bt_dbus.sh` / `bt_fetch.sh`). Device paths: `^${adapter}/dev_[^/]+$` (skip GATT children).
- ACCENTUM Plus battery is GATT `0x2A19` on the LE bearer (`org.bluez.Bearer.LE1`), not HFP. Snapshot via `bt_dbus_refresh_headset_battery` (connect, ReadValue, **Disconnect LE**) so A2DP does not share the radio. Cache TTL is 20 min; expired values are omitted (that is how 10% stuck). Popup may kick one background snapshot if cache is cold — 60s cooldown, never poll `Bearer.LE1.Connect`. Do not put battery on the TopBar pill. `DisablePlugins` includes `battery` so BlueZ does not `StartNotify`. Do not re-enable the headset plugin for AT battery.
- Keep A2DP-only: no HFP/headset autoswitch, no `bluez5.roles` HFP/BAP. Citrix capture would flip profile and kill the headset. Use webcam mic for calls.
- Do not re-enable `bluetooth.autoswitch-to-headset-profile` without an explicit plan.
- Keep **aptX HD** on ACCENTUM Plus. In-game drops were PipeWire underruns (`out of buffers`, then `Failure in Bluetooth audio transport`): games request quantum 32, HD is 44.1 kHz, and the graph was locked to 48 kHz. `default.clock.allowed-rates` includes 44100; bluetooth sinks pin `pulse.min.quantum` to 1024/44100. Do not cap `bluez5.codecs`. Do not add LDAC/BAP. After a transport error WirePlumber leaves the sink in `error` — BlueZ may recreate `fd0` but game audio does not come back; the headset has to be power-cycled.

## Citrix

`modules/packages/work.nix`: wrap with `GDK_BACKEND=x11` (NVIDIA WebKit crash on Wayland).
`RememberUsername=true` via `overrideAttrs` on `AuthManConfig.xml`. **Never** store the MS username or password in the flake. Leave `SavePasswordMode` alone. Rebuild of this package is slow. `icasessionmgr` extra wrap must use `wrapProgramShell` (`--run ulimit`); `wrapGAppsHook` makes `wrapProgram` a C wrapper that rejects `--run`.

**Store→HDX handoff:** AuthManager forks `$ICAROOT/adapter` (not PATH) as a UIPipe child. The vendor adapter waits on a session hash and exits in ~10s when ServiceRecord cannot supply one — ICA is written to `~/.ICAClient/cache/` but `wfica` never stays up. Signature: `PipeInit() succeeded` then `could not get hold of hash!` then `UIPipeTask::DoTask finished!` ~10s later (the hash ERR also appears on healthy launches; the 10s child exit is the fault). Direct `wfica -icaroot … file.ICA` works. Fix: `citrix-adapter-wfica-shim.sh` replaces `$ICAROOT/adapter` and `$out/bin/adapter` — strips UIPipe-only flags (`-WI`, `-transactionid`, …) and `exec`s `wfica`. Also wrap `$ICAROOT/wfica` with the X11/WebKit flags (icasessionmgr/shim exec that path). Do not restore the vendor UIPipe adapter. After this package changes, quit SelfService (by PID, not `pkill -f`) before testing.

Entra/SAML login stays on the **embedded WebKitGTK dialog** — leave `AADSSOWithFido2AuthenticationEnabled` / `SharedAuthContextEnabled` / `FIDO2Enabled` at the vendor `false`. Setting them true routes login to `FIDO2AuthBrowser` over `ctxaadsso://`, and since Citrix only launches known browser names it opens a bare Firefox with no MS session or passkeys instead of a popup; the attempt then ends as `LogonResult_CancelledByUser` and Citrix never opens. (`InteractionNotAllowed` just before that is the normal failed silent-SSO probe, not the fault.) The `WEBKIT_DISABLE_COMPOSITING_MODE` / `WEBKIT_DISABLE_DMABUF_RENDERER` flags exist for that embedded dialog on NVIDIA; `firefox` on PATH is only for links opened from the store UI. `gnome-keyring` is Secret Service only — leave `gcr-ssh-agent` off (1Password).

**Stale Citrix daemons survive `nh os switch` and pin the old store path.** `systemd.services.citrix-reap-stale` (in `work.nix`) kills only `ServiceRecord` / `AuthManagerDaemon` / `PrimaryAuthManager` / `selfservice` / `ctxwebhelper` / `storebrowse` whose exe or cmdline is a *previous* `citrix-workspace` store path. It does **not** touch `wfica` or `icasessionmgr` (live session). The unit embeds the current package path, so it re-runs on switch only when Citrix itself changed. Manual check: compare `ps -eo pid,args` against `readlink -f /opt/Citrix/ICAClient`. Kill leftover PIDs by number — `pkill -f selfservice` matches your own shell. Signature if it still happens: nFactor hands over `m_StartUrl=.../nf/auth/startWebview.do`, no `PrimaryAuthManager` window maps, ~3s later `LogonResult_CancelledByUser` / "The user clicked cancel" with nothing clicked. Healthy: floating `PrimaryAuthManager` popup, then `CTokenCaches::AddAgSession`.

Zoom-inside-Citrix uses `zoomvdi-universal-plugin` **7.0.11.27050**, matching the VDI Zoom client (7.0.11). Version parity is mandatory: a 6.6.x plugin against a 7.0.x client loads, spawns the helper, fails the handshake and exits in ~1s loops with no error — looking exactly like a local crash. Check the client version in the VDI (Zoom → About) before debugging the host. Bump via `version`; the URL derives `shortVersion` from it, and builds are listed on Zoom's "VDI releases and downloads" KB. 7.0.x bundles Qt 6.8 (6.6.x was Qt 5.15) and needs `zstd`. `libZoomPlugin.so` is registered as Citrix `ZoomMedia.so`. Citrix execs the sibling `$plugin/zoom` inheriting wfica's `LD_LIBRARY_PATH` (no `libz`), so the helper must be self-sufficient: `patchelf --force-rpath --set-rpath` plugin+Qt+Nix libs onto `zoom`, `aomhost` and `crash_processor`. Also symlink Nix `.so`s into the plugin dir and `L+ /usr/lib/zoomvdi-universal-plugin`. `DT_RPATH` on the executable is *not* sufficient on its own — the loader prunes that list as it walks the dependency graph, so late lookups (`libxkbcommon`, `libz`, `libzstd`, `libEGL`) miss it and fall through to the system paths. `autoPatchelf` the bundled `Qt/lib`, `Qt/plugins` and `Qt/qml` too so every object carries its own runpath; the vendor Qt tree ships with none. Verify with `ldd`: `env -u LD_LIBRARY_PATH ldd $plugin/zoom` must report zero `not found`. Do not `buildFHSEnv` the helper. After a Citrix wrap change, `pkill icasessionmgr`. Do not bump the plugin past the VDI client version.

**`$plugin/zoom` must stay the unwrapped vendor ELF.** The plugin spawns it as its own sibling (no path is baked into the `.so`; the ini's `PATH` is only the child's `PATH`, and `BIN` is not read at all) with `--action=ZoomAVProcess --ipc_name=<GUID> --parent_pid=<wfica>`, the helper connects back to abstract socket `<GUID>zoomhdc`, and the plugin then authenticates the peer against the process it spawned — pid, `/proc/<pid>/cmdline` **and `/proc/<pid>/exe`**. Any exec wrapper (shell, `makeWrapper`, C shim) leaves `exe` pointing at the wrapper's target: the plugin closes the socket right after the handshake (15 `sendmsg`, then `recvmsg` returns 0) and the helper exits 0 in a ~2s retry loop that looks exactly like a local crash. So the wrapper's jobs are done without exec — libraries via `DT_RPATH`, environment and signals via a `DT_NEEDED` constructor (`libzoomvdifix.so`, `patchelf --add-needed`).

That constructor covers two things. wfica spawns the helper with SIGCHLD ignored, and an ignored disposition survives exec, so GLib's `g_spawn_sync` gets ECHILD probing `pactl --version`, Zoom logs "no pactl and pacmd found", and AV/VPT exit in ~1s loops (Settings never opens). Nothing outside the process can undo an inherited `SIG_IGN`. Reset **only** SIGCHLD — resetting SIGPIPE to `SIG_DFL` would turn a closed socket into a fatal signal. It also forces `QT_QPA_PLATFORM=xcb`: the bundle ships `libqxcb.so` but no usable wayland plugin, so an inherited `WAYLAND_DISPLAY` alone makes Qt abort. Check with `grep SigIgn /proc/<pid>/status` (bit 17 clear) and `readlink /proc/<pid>/exe`.

Note the helper does **not** inherit the session's Qt environment: wfica exports no `QT_PLUGIN_PATH`/`QML2_IMPORT_PATH`, so qt5ct/qt6ct contamination is not a real failure mode (it only appears when running `$plugin/zoom` from a login shell). The bundled `qt.conf` (`Prefix=./Qt`) resolves relative to the binary's own directory, which is another reason `zoom` must live in `$plugin` rather than behind a wrapper.

Do not add a tracing hatch to `$plugin/zoom`: `ptrace_scope=1` blocks attaching to a wfica child and any wrapper perturbs the identity checks above, so the hatch reproduces the failure it is meant to diagnose (even `strace -D`, which fixes only the pid). Trace by temporarily `--add-needed`-ing a logging shim instead. Running `$plugin/zoom` by hand falls back to the desktop `~/.zoom` dir and logs sqlcipher hmac failures — an artifact, not the bug; real runs use `~/.zoomvdi`.

`extraLibs` needs `alsa-lib` (Qt audio), `libxcursor`+`libxinerama` (dlopen'd by name from Qt xcb), `libxcomposite`+`libdrm` (SHAREOFFLOAD). Diagnose via `~/.zoomvdi/logs/zoom_stdout_stderr.log` and `coredumpctl` (Qt xcb aborts show as `createPlatformIntegration` SIGABRT). "VDI plugin not connected" inside Zoom with a healthy helper points at `VdiBridge::IsVersionMatch` — compare the packaged plugin version against the VDI-side Zoom version.

## Boot / disks

- Match disks by **MODEL**, not `nvmeN`. NixOS is the **Samsung 980 PRO** (currently `nvme1n1`): one **ext4** root + ~1G ESP UUID `EC21-2EC2`. Windows 11 is the **WD SN850X** (currently `nvme0n1`). Full wipe/reinstall steps: repo `README.md`.
- `/boot` is the **NixOS ESP** (~1G on the Samsung SSD), not the Windows ESP.
- Limine `extraConfig` is **prepended**. Put `default_entry: 3` first (1 Windows, 2 NixOS folder, 3 latest generation). A trailing `default_entry` is ignored.
- NIC: Realtek RTL8125 via out-of-tree `r8125` (`r8169` blacklisted). Ethernet `enp14s0`. Do not switch back to `r8169`.
- RGB: `modules/hardware/openrgb.nix` (`services.hardware.openrgb`, `openrgb-with-all-plugins`, AMD `i2c-piix4`). MSI X670E Mystic Light + ARGB headers + RAM. `JRAINBOW1`/`JRAINBOW2` are 12 LEDs each (`openrgb-sizes.ors`); size 0 hides those zones. Does not drive NuPhy Node 100, MCHOSE K7 Ultra, GCB200, or fan PWM. Do not add `fan_config=msi_alt1` here (that is nct6687d / CoolerControl). Do not add Artemis.
- Steam DNS: `services.dnsmasq` on 127.0.0.1, NM `dns = "none"`, upstream the LAN Pi-hole `192.168.0.105` (`modules/networking/default.nix`). Local cache + `dns-forward-max=32` so Steam does not saturate Pi-hole (that is what made nix fail to resolve `nix-community.cachix.org`). Do not also set NM `dns = "dnsmasq"`. Do not add public resolvers as extra `server=` entries — dnsmasq will skip a slow Pi-hole and leak ads. `services.resolved` stays off. IPv6 already disabled for Steam's "downgrading to ipv4-only" stall.

## OpenResearch

OpenResearch (openresearch.sh, alphaXiv) is an agentic ML research desktop; Linux ships as an AppImage. `homeManager.dev` packages it the same way: `appimageTools.extract` + `buildFHSEnv` over `appimageTools.defaultFhsEnvArgs` (the bundled binary needs `/lib64/ld-linux-x86-64.so.2`, NixOS' stub-ld here). The runScript is a `writeShellScript` that **unsets `APPIMAGE`** before `appimage-exec.sh -w` — load-bearing: orx classifies its install from that variable, and with it set the app behaves as a self-updating AppImage (rewrites the desktop entry to the store AppImage path and downloads itself); unset, the `/nix/store` path lands in its `InstallChannel::Nix` and updates stay with the flake. The `orx` CLI agents drive is a separate static-musl binary from the same release (plain `runCommand`, no patchelf); GUI and CLI share `~/.config/openresearch`. Entry + icon install into the FHS env's `share/`, and `xdg.dataFile."applications/openresearch.desktop"` (`force = true`) guards against an entry a manual upstream AppImage run wrote shadowing the profile's via XDG_DATA_HOME. Bump = `openresearchVersion` + both fetchurl hashes in `modules/packages/dev.nix`.


## Epic Games Launcher

The official Epic Games Launcher in `nixos.gaming` (`modules/packages/gaming.nix`) is the Tauri-based rework ("preview") — the classic launcher never shipped for Linux. Epic serves the AppImage only through the Cloudflare-fronted store page with no versioned URL, so it is pinned with `pkgs.requireFile` (hash of the manually downloaded `EpicGamesLauncher-x86_64.AppImage`); after grabbing a new build from https://store.epicgames.com/en-US/install/ng/, bump the hash and re-satisfy the build with `nix-store --add-fixed sha256 ~/Downloads/EpicGamesLauncher-x86_64.AppImage`. Packaging mirrors OpenResearch: `appimageTools.extract` + `buildFHSEnv` (the bundle is self-contained — WebKitGTK 4.1, GStreamer, gnutls — so `defaultFhsEnvArgs` needs no extra packages), runScript **unsets `APPIMAGE`** (the launcher keys its AppImage self-updater on that variable), and `extraInstallCommands` installs the bundled desktop entry (which carries the `x-scheme-handler/com.epicgames.launcher` deep-link handler) with `Exec` rewritten to the wrapper plus the three hicolor icons. AppRun's GTK hook forces `GDK_BACKEND=x11` (Tauri's Wayland backend crashes); needs XWayland. App state lives in `~/.local/share/com.epicgames.eglv2/`.

## Hermes Desktop

Hermes Desktop (hermes-agent.nousresearch.com) is `modules/packages/hermes-desktop.nix` (`homeManager.hermesDesktop`, `#nixos` only) — Nous Research's Electron shell for the Hermes agent. Linux has no prebuilt download, so `hermes-desktop-setup` runs the hash-pinned official installer (`--include-desktop --non-interactive`), which clones the checkout to `~/.hermes/hermes-agent`, stages the uv/Python/Node toolchain and builds the desktop app into `apps/desktop/release` — upstream's Linux path runs electron-builder `--dir`, so the artifact is the unpacked directory app `release/linux-unpacked/{h,H}ermes`, not an AppImage; rerunning it is the update path (also how node-gyp native modules like node-pty get a toolchain — the wrapper's `runtimeInputs` include gnumake/gcc/binutils, since NixOS has no system `make`). The checkout floats on main — only `install.sh` itself and `apps/desktop/assets/icon.png` are pinned via fetchurl hashes. `hermes-desktop`/the desktop entry exec a `buildFHSEnv` over `appimageTools.defaultFhsEnvArgs` + `libsecret` (Electron wants `/lib64/ld-linux-x86-64.so.2` plus GTK/NSS, none of which NixOS exposes). The env's `runScript` is a `writeShellScript` runner that prefers the newest `release/*.AppImage` (exporting `APPIMAGE` for electron-updater, the opposite of the OpenResearch rule which unsets it) and falls back to the `linux-unpacked` binary — it must NOT be the buildFHSEnv default `"bash"`: the default makes the generated `/init` do `exec bash "$@"`, so bash script-mode-fails on every ELF binary with `cannot execute binary file`. `appimageTools.appimage-exec` rides in `targetPkgs` (as in dev.nix's openresearch chroot) so an AppImage would run too. The app registers `hermes://` deep links and bridges to the Pi over a `desktop-ssh` ControlMaster. The bootstrap toolchain's prebuilt binaries need `programs.nix-ld` + `/etc/ssl/cert.pem`, mirrored from the Pi block into the `#nixos` host config (plus X11/Wayland libs for the staged cua-driver check). First run: `nh os switch`, then `hermes-desktop-setup` (10–30 min), then launch. The old `nixos.hermesDesktop` WakeOnLAN/SSH module was deliberately deleted and stays deleted.

## Capy

Capy (capy.ai) is `modules/packages/capy.nix` (`homeManager.capy`, `#nixos` and `#mango`). Linux also ships an AppImage and a `.deb`; both self-update, which cannot rewrite a Nix store path. The module pins the packager **tarball** (`https://downloads.capy.ai/stable/capy-<version>-x64.tar.gz`, listed beside `latest-linux.yml`). With `APPIMAGE` unset and no `resources/package-type` file, Capy marks the install unmanaged and says updates come from the package. The electron binary wants `/lib64/ld-linux-x86-64.so.2`, so it runs in a `buildFHSEnv` over `appimageTools.defaultFhsEnvArgs` plus `libsecret`, `xdg-utils`, and `desktop-file-utils`. The `runScript` is a `writeShellScript` that execs `capy --no-sandbox` — not buildFHSEnv's default `"bash"`. On Linux, Capy registers `capy://` by symlinking `~/.local/share/capy/protocols/capy` at `process.env.APPIMAGE || process.execPath`. That binary cannot start outside the chroot, so the unpack step rewrites that **one** occurrence to `process.env.CAPY_BIN || process.execPath`. `CAPY_BIN` is eight characters, the same length as `APPIMAGE`; a longer name shifts asar offsets and the app will not start. The `capy` launcher exports `CAPY_BIN` as its own realpath. Do not set `APPIMAGE` (that enables electron-updater). Do not revert the asar string. Asar integrity is off on 0.4.7. Bump `capyVersion` and the fetchurl hash together. The unpack derivation fails closed if the string is missing, not unique, or the file size changes.

## Secrets / safety

No MS/Citrix credentials, Wi-Fi PSKs, or OpenWeather keys in the flake. Weather key lives in `~/.config/hypr/openweather.env` (gitignored live file).
