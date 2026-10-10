# Gaming Mode (SteamOS-style gamescope session)

`#nixos` keeps Hyprland as its default desktop and adds a second, parallel
Wayland session called **Gaming Mode (Steam)**. It is a gamescope session that
runs Steam's Deck UI — the same shape as SteamOS Game Mode — and it owns the
display while it runs, so VRR and fullscreen behave like a console rather than
like a game inside a desktop compositor.

Implemented in `modules/desktop/gaming-mode.nix`, imported by
`modules/hosts/nixos-hyprland.nix` as `nixos.gamingMode`.

## Selecting it

`services.greetd` already enumerates the session files and supports
`--remember-session`, so no greeter change was needed. At login the session list
is:

```text
Gaming Mode (Steam)
Hyprland
Hyprland (uwsm)
```

Pick Game Mode and tuigreet remembers it. `Hyprland` (`start-hyprland`) stays
the fallback command, so forgetting or clearing the remembered session returns
to the desktop.

To go back the other way, exit Steam from its power menu: Steam exits, gamescope
exits, and greetd restarts the greeter.

## What the session runs

```bash
export XDG_CURRENT_DESKTOP=gamescope
export XDG_SESSION_DESKTOP=gamescope
export PATH="…standard NixOS session PATH…:$PATH"   # see below

exec gamescope \
  --steam \
  --adaptive-sync \
  --prefer-output=HDMI-A-2,HDMI-A-1 \
  -W 3440 -H 1440 \
  -- steam -gamepadui -pipewire-dmabuf
```

`--steam` is what makes this SteamOS-like: gamescope itself detects the display
and driver capabilities and exports the `STEAM_GAMESCOPE_*` variables (VRR,
tearing, HDR, NIS) plus `STEAM_USE_MANGOAPP`, `STEAM_MULTIPLE_XWAYLANDS`,
`ENABLE_GAMESCOPE_WSI` and `SDL_VIDEO_DRIVER` for the Steam child process. Those
names are produced by gamescope (`src/steamcompmgr.cpp`), so the session
deliberately does **not** set them itself — doing so would advertise features
gamescope did not actually detect for this display.

**`--mangoapp` is deliberately not passed.** SteamOS pairs gamescope with a
gamescope-rendered `mangoapp` overlay, but that is a *second* HUD stacked on
top of MangoHud, and MangoHud is the overlay this setup already uses
everywhere — so Game Mode passes no `--mangoapp` and shows exactly one HUD,
identical to the desktop's.

gamescope still exports `STEAM_USE_MANGOAPP` for Steam regardless (it is set
under `if (steamMode)` with `overwrite = 0`, not under `--mangoapp`), which is
harmless while no `mangoapp` process exists. If Steam's Deck-UI overlay control
ever produces a second HUD anyway, `export STEAM_USE_MANGOAPP=` in the session
script is the lever — gamescope will not overwrite the now-empty value.


## Steam launch options

Per-game launch options live in Steam's own user config
(`~/.local/share/Steam/userdata/<id>/config/localconfig.vdf`), which both
sessions share: same user, same `$HOME`, same `programs.steam.package`, same
Proton/compat-tool mapping. So they carry over unchanged, including the
`%command%` suffixes and `PROTON_ENABLE_HDR=1`/`DXVK_HDR=1` prefixes.
Two things were needed to make that actually true:

**1. `MANGOHUD=1` must stay on.** MangoHud's Vulkan layer is gated by
`enable_environment: { "MANGOHUD": "1" }` in `MangoHud.x86_64.json`, so a bare
`MANGOHUD_CONFIGFILE=…` launch option does nothing on its own — it only takes
effect because the Steam wrapper exports `MANGOHUD=1` globally. Disabling that
in Game Mode would have silently dropped the `fps_limit` caps and per-game
profiles from every one of those launch options.
Game Mode therefore keeps the same wrapper behaviour as the desktop:
`MANGOHUD=1` on, one MangoHud overlay, driven by whatever
`MANGOHUD_CONFIGFILE` the game's launch option selects.

**2. PATH.** greetd hands sessions the minimal PATH from `greetd.service`
(coreutils/findutils/gnugrep/gnused/systemd only) and there is no
`/etc/environment` to extend it. Launch options resolve helpers *by name*, so
`gamemoderun %command%` and `env -u TZ …` would not have resolved. The session
restores the standard NixOS session PATH
(`/run/wrappers/bin:/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin:…`)
before starting gamescope.

Per-game Proton version, compat-tool selection, cloud saves and shader caches
also live in the shared Steam install and are unaffected.


## Quiet Game Mode

Nothing is killed or masked for Game Mode. It is quiet by construction: every
desktop service the shell depends on is bound to `graphical-session.target`
(Serpantinum's `systemd.target` default, `hypridle`'s `systemdTarget`,
`hyprpolkitagent`, `ydotoold`, `hyprexpose`), and a gamescope session is started
by greetd directly without ever starting that target. Serpantinum/Quickshell,
the idle daemon and the polkit agent therefore never come up and do not compete
with gamescope for the display or for GPU time.

Home Manager is unaffected either way: its activation unit is a system service
ordered `before = systemd-user-sessions.service`, so `~/.config/MangoHud/*` and
`steam_dev.cfg` are already in place before any session starts.

## Verifying after a switch

```bash
# Session file and command actually installed
ls -l /run/current-system/sw/share/wayland-sessions/ 2>/dev/null
cat $(readlink -f /nix/var/nix/profiles/system)/share/wayland-sessions/gaming-mode.desktop

# Game Mode logs (greetd owns the session process)
journalctl -b -u greetd
journalctl -b _COMM=gamescope

# gamescope's own stdout/stderr, which greetd otherwise discards. This is
# the only place session-level failures show up.
cat "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gamescope.log"

# Inside the session: is gamescope on the right connector/mode, and is
# Steam seeing the capability it needs?
gamescopectl  # gamescope control socket
grep -a gamemode /proc/$(pgrep -x steam | head -1)/environ 2>/dev/null
```

Acceptance for a first run: the Deck UI appears, the display runs 3440x1440 at
175 Hz in HDR with VRR offered in Steam's performance settings, a game launches
with exactly one MangoHud overlay, and exiting Steam returns to the greeter with
Hyprland still selectable.

Inside Game Mode, confirm the launch-option plumbing:

```bash
# PATH must include the system profile, otherwise gamemoderun will not resolve
echo "$PATH" | tr ':' '\n' | grep -E 'current-system/sw/bin|profiles/per-user'
command -v gamemoderun

# MangoHud must be enabled, otherwise MANGOHUD_CONFIGFILE is ignored
echo "${MANGOHUD:-unset}"

# and gamescope must not have started its own overlay process
pgrep -a mangoapp || echo 'no mangoapp — good'
```

Then launch a game that caps FPS through a `MANGOHUD_CONFIGFILE` launch option
(e.g. Onimusha at 150 fps) and check the cap actually applies.

## Troubleshooting in Game Mode

Confirmed from the first real session (2026-09-26):

- **`gamemoderun` works.** `gamemoded` starts and attaches to the game, so the
  launch-option PATH restore above is doing its job.
- **The CPU governor was never switched — and that was never Game Mode's
  fault.** `gamemoded` logs `pkexec ... cpugovctl set performance: Not
  authorized` in *every* session, desktop included (128 occurrences across the
  journal). GameMode's own `.policy` ships `allow_any`, `allow_inactive` and
  `allow_active` all set to `no`, so polkit denies outright and **no
  authentication agent can change that** — only a rule can. `nixos.gaming` now
  carries one for the two CPU helpers, scoped to active local `wheel` users.
  `Inhibit` on `org.freedesktop.ScreenSaver` also fails with `No route to
  host`, which is expected with no portal and harmless (gamescope handles idle).
- **greetd discards gamescope's output**, which is why the session keeps its own
  copy at `${XDG_RUNTIME_DIR}/gamescope.log` (see above). Without that file there
  is no record of gamescope's own errors at all.
- **Steam's side** lives in `~/.steam/steam/logs/`: `gameprocess_log.txt` shows
  every tracked process plus the exact launch-option expansion, and
  `console-linux.txt` carries the Proton/vkd3d/DXVK output including the
  `[Gamescope WSI]` lines.

When a game's process appears in `gameprocess_log.txt` but no window ever shows,
work down this list. The first is the current leading suspect:

1. **HDR mismatch.** Hyprland and MangoWM both run the MAG 341C in HDR
   (`cm = "hdr"`, `bitdepth = 10` / `hdr:1`), and Onimusha's launch options set
   `PROTON_ENABLE_HDR=1`. gamescope only offers HDR when given `--hdr-enabled`,
   which the session now passes — before that the game asked for an HDR
   swapchain that the compositor was not providing, a mismatch the desktop
   never had. To isolate it, drop `--hdr-enabled` from the session *and*
   `PROTON_ENABLE_HDR=1` from the launch options together.
2. **Frame generation.** `FrameGenerationMode=On` in `config.ini`. Frame
   generation under gamescope/vkd3d is a known hang, and this game already
   carries a `config.ini.backup-before-framegen-disable-*`, so it has bitten
   before.
3. **The game's persisted display mode.** RE Engine titles store a
   `FullScreenDisplayModeIndex` that indexes *the monitor's* mode list.
   gamescope advertises a different and much smaller mode list, so an index
   picked on Hyprland can be meaningless under gamescope. Back the file up and
   let the game regenerate it.

`PROTON_LOG=1` in the launch options gives a full `~/steam-<appid>.log` and is
the fastest way to see where Proton stops. Also check
`${XDG_RUNTIME_DIR}/gamescope.log`, which is the only record of what gamescope
itself said.

## Getting out of a frozen Game Mode

A hung gamescope holds the only VT and no second getty is waiting (the greeter
conflicts `getty@tty1`), so the instinct is a hard reset. Two routes out:

- **`Ctrl+Alt+F2`.** gamescope links `libseat`, so it releases DRM master on a
  VT switch, and logind spawns `autovt@tty2` → `getty@tty2` on demand
  (`NAutoVTs` is at its default of 6, and the `autovt@` alias resolves). Log in
  and `pkill gamescope`; greetd then brings the greeter back. Unverified —
  worth confirming during a healthy session before you need it.
- **SSH.** `pkill gamescope` over SSH/Tailscale works no matter what the display
  is doing, and is the only route that does not depend on the GPU still being
  responsive. Prefer this one when testing risky flags.

Do not count on `Alt+SysRq+K` as an escape: `kernel.sysrq` is 16, which enables
only the sync key, so SAK is disabled.

## Tuning knobs

- **Resolution / refresh** — `outputWidth`/`outputHeight` in
  `modules/desktop/gaming-mode.nix` match the MAG 341C and Hyprland's monitor
  profile. They are passed explicitly instead of relying on gamescope's output
  defaults. Refresh comes from the highest-refresh mode at that size.
- **Connector** — `connectorPreference` mirrors the Hyprland comment: NVIDIA
  exposes the same physical port as `HDMI-A-2` or `HDMI-A-1` depending on the
  driver, so `--prefer-output` lists both.
- **HDR** — `--hdr-enabled` is passed, matching the Hyprland/MangoWM monitor
  profile. To also match Hyprland's `sdr_max_luminance = 203` for SDR content
  shown inside HDR, add `--hdr-sdr-content-nits 203` (gamescope defaults to
  400). `--hdr-itm-enabled` is not used. Drop `--hdr-enabled` if it interacts
  badly with a specific game.
- **Tearing** — add `--immediate-flips` for the SteamOS "allow tearing" toggle.
- **Fuller SteamOS parity** — adding `-steamdeck` to the Steam arguments makes
  the client treat the machine as a Deck. Left out by default because it changes
  client behaviour beyond the UI; try it if you want the power menu to read
  "Exit to Desktop" and Deck presets in the performance overlay.
- **SteamOS-style overlay instead** — add `--mangoapp` to the gamescope
  arguments to have gamescope render its own `mangoapp` HUD. That is what
  SteamOS does, but here it stacks a second overlay on top of MangoHud (and
  `pkgs.mangohud` must go back into the session's `runtimeInputs`, because
  gamescope resolves `mangoapp` through `PATH`). One MangoHud is the default.
- **Compositor priority** — `programs.gamescope.capSysNice` and gamescope's
  `--rt` are not used. If frame pacing warrants it, enable `capSysNice` and
  change the session's `gamescope` binding to
  `"${config.security.wrapperDir}/gamescope"`, because nixpkgs then installs
  gamescope as a capability wrapper rather than a profile package.

## Rollback

- Pick `Hyprland` in the greeter. This is the normal `#nixos` generation and is
  unaffected by Game Mode.
- From the boot menu, select the last known-good generation.
- To remove the feature, drop `nixos.gamingMode` from
  `modules/hosts/nixos-hyprland.nix`. `nixos.gaming` then re-exposes nixpkgs'
  bare `steam.desktop` session, and `Hyprland` remains the default.

## Known limitations

- **Only partly exercised.** Game Mode has been booted and reached Steam (the
  duplicate-HUD report is what removed `--mangoapp`), and one game (Onimusha)
  has been launched in it — that launch reached the game process and then hung
  with no window (see Troubleshooting). The mode/connector, VRR, and
  exit-to-greeter paths are still unverified. The session file, greeter wiring,
  wrapper script and Steam profile were verified by evaluation and by a full
  system build.
- **NVIDIA.** gamescope with the proprietary/open DRM backend is the least
  well-trodden path here. If the session fails to take the display, check
  `journalctl -b -u greetd` first and try dropping `--adaptive-sync` and
  `-W`/`-H` before changing anything else.
- **No polkit agent or portal in Game Mode.** Anything needing an authentication
  prompt (mounting a disk, some settings) has nowhere to appear, and Steam's
  file pickers fall back to their own UI. This does *not* affect GameMode's CPU
  helpers — those are denied by GameMode's own policy and fixed by the rule in
  `nixos.gaming`, not by an agent.
- **Capability flags are only as good as detection.** If Steam's Deck UI does
  not offer VRR, that reflects what gamescope detected, not a missing variable.
