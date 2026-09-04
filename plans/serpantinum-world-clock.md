# Serpantinum World Clock Plan

## Context

Extend the current Serpantinum top bar with a dedicated world-clock control. Clicking it should open a futuristic popup that remains visually consistent with the existing bar, presents several configurable regional clocks, and includes an interactive 3D Earth visualization of time across the world.

Current repository and pinned-upstream findings:

- `modules/desktop/serpantinum.nix` is already an uncommitted migration from a 1,663-line custom shell overlay to Serpantinum's official NixOS/Home Manager modules plus one strict `overrideAttrs` patch. Treat that current file as the baseline, preserve its desktop-Bluetooth substitutions, and do not resurrect deleted legacy patches.
- The flake pins `ilyamiro/serpantinum` at `26e40a34451939f6ea553454fd3f55b36b3d4ac7`; implementation anchors must target that revision and fail the build if upstream text changes.
- `TimeDateWidget.qml` owns the existing clock/date pill and launches the calendar through generic `qs_manager.sh toggle calendar`. The generic manager and `Main.qml` IPC already accept any target registered by `WindowRegistry.js`, so `qs_manager.sh` does not need a new dispatch path.
- `TopBar.qml` hard-codes module IDs and geometry in many places. To avoid a fragile, wide patch, the new globe will be a visually separate `IconButton` beside the clock but remain inside `TimeDateWidget`'s measured root.
- `Main.qml` creates popup components from `WindowRegistry.js`, writes the active target to `Caching.runDir/current_widget`, closes on outside-click/Escape, and animates popup geometry. The world clock can reuse this lifecycle by adding one registry entry and one preloader-list item.
- `Config.qml` already exposes `Config.setSetting(key, value)` and watches `~/.config/serpantinum/settings.json`; a top-level `worldClock` object can therefore be edited live without a parallel state file.
- The Home Manager settings schema is freeform and recursively merges Nix values over the bundled template, but its activation installs only when `settings.json` is absent. A narrowly scoped merge-once/missing-key activation is required to seed the selected defaults for existing installations without overwriting later UI edits.
- QML's JavaScript `Date` only formats UTC/the current system zone. Accurate arbitrary IANA zones and DST therefore require the local timezone database rather than offset arithmetic.
- Upstream currently omits `qt6.qtquick3d` from its QML path. The package integration must add that module before using a true `View3D`/`#Sphere` globe.

## Approach

Keep the existing local clock/calendar behavior, but widen `TimeDateWidget` to host a second, independently styled globe button. That button will call `qs_manager.sh toggle worldclock` and highlight while `Caching.runDir/current_widget` contains `worldclock`. Register a centered, bar-aware popup in `WindowRegistry.js` and preload it through `Main.qml` so it receives the same open/close, outside-click, Escape, scaling, and morph animations as other Serpantinum panels.

Implement the popup as a split futuristic panel: a searchable/editable clock rail on the left and an interactive Qt Quick 3D Earth on the right. Use Serpantinum's `Scaler`, `ThemeBackend` palette/font/radius, `IconButton`, translucent `surface*` layers, restrained blue/mauve/teal glow, and the Calendar popup's staged intro style. The globe will use `View3D`, a textured built-in `#Sphere`, a solar `DirectionalLight` for the day/night terminator, theme-colored city markers, drag rotation, wheel zoom, click-to-focus from either a card or marker, and a subtle idle rotation only while open.

Use one packaged Python `zoneinfo` helper backed by pinned `pkgs.tzdata`. It will list canonical IANA zones and coordinates from `zone1970.tab`, detect the local zone, and return all selected clocks in one JSON snapshot. Run it once when the popup opens and at minute boundaries only while visible; never use network APIs, hard-coded UTC offsets, or one process per city. Persist add/remove/reorder and 12/24-hour preferences through the existing top-level `Config.setSetting("worldClock", ...)` path.

The confirmed defaults are UI-editable with Nix-provided initial values: Local, UTC, New York (`America/New_York`), London (`Europe/London`), and Tokyo (`Asia/Tokyo`). Existing settings win over defaults on every activation, including an intentionally empty region list.

## Files to modify

- `modules/desktop/serpantinum.nix` — compose Quickshell with `qt6.qtquick3d`, set the default `worldClock` settings, install the overlay files/assets, run the strict upstream patcher, and seed only a missing `worldClock` key in an existing settings file.
- `modules/desktop/serpantinum/world-clock/patch-serpantinum.py` — strict, revision-specific patches for installed `TimeDateWidget.qml`, `Main.qml`, `WindowRegistry.js`, and the bar module `qmldir`; abort if any expected anchor is absent.
- `modules/desktop/serpantinum/world-clock/WorldClockButton.qml` — separate top-bar globe control, popup-active watcher, hover/active theme states, and generic `qs_manager` launch.
- `modules/desktop/serpantinum/world-clock/WorldClockPopup.qml` — split popup, clock cards, edit/search controls, persistence, helper process, keyboard/focus behavior, and intro transitions.
- `modules/desktop/serpantinum/world-clock/WorldClockGlobe.qml` — `View3D` Earth scene, camera/input controls, sun direction, markers, focus animation, and visibility-gated motion.
- `modules/desktop/serpantinum/world-clock/world_clock.py` — batched `zoneinfo` snapshots plus IANA zone/coordinate catalog from pinned tzdata.
- `modules/desktop/serpantinum/world-clock/earth-land.svg` — optimized local equirectangular schematic texture; no runtime download.
- `modules/desktop/serpantinum/world-clock/ASSET-SOURCES.md` — texture source, license/public-domain status, and processing notes.

Installed upstream files changed by the patcher (not vendored):

- `$out/share/serpantinum/quickshell/bar/modules/TimeDateWidget.qml`
- `$out/share/serpantinum/quickshell/bar/modules/qmldir`
- `$out/share/serpantinum/quickshell/Main.qml`
- `$out/share/serpantinum/quickshell/WindowRegistry.js`

## Reuse

- Existing `serpantinum.overrideAttrs` / `postInstall` flow and `--replace-fail` philosophy in `modules/desktop/serpantinum.nix`.
- `TimeDateWidget.qml` sizing/startup animation and its unchanged calendar click target; the globe is a sibling hit target, not a replacement.
- Generic `qs_manager.sh` → `Main.qml.handleCommand()` dispatch; no new shell command branch.
- `WindowRegistry.js` geometry and `Main.qml` popup caching, morph, outside-click, and Escape lifecycle.
- `Config.setSetting()` / settings `FileView`, plus Home Manager's freeform `programs.serpantinum.settings` support.
- `ThemeBackend`, `Scaler.s()`, `IconButton`, and visual/intro patterns from `CalendarPopup.qml`.
- Quickshell `Process` + `StdioCollector` for one batched helper call, and `FileView` for the existing active-widget runtime file.
- Qt Quick 3D's built-in `#Sphere`, `View3D`, `PerspectiveCamera`, `PrincipledMaterial`, `DirectionalLight`, and `Repeater3D`; no custom mesh pipeline.

## Steps

- [x] Add a reproducible package overlay: pass upstream `package.nix` a collision-checked `symlinkJoin` of its existing Quickshell package and `qt6.qtquick3d` so the existing wrapper's QML/plugin paths include both; retain the current Bluetooth patch, copy the focused world-clock overlay, substitute the pinned tzdata path into the helper, and execute the strict patcher.
- [x] Define `programs.serpantinum.settings.worldClock` defaults with `hour12 = null` (inherit the bar format), `showSeconds = false`, globe preferences, and ordered Local/UTC/New York/London/Tokyo region objects.
- [x] Add an atomic Home Manager activation step after Serpantinum's settings activation using `${pkgs.jq}/bin/jq`: insert `worldClock` only when the top-level key is absent, validate the temporary JSON, then rename it into place; never replace an existing object or an empty user region list.
- [x] Patch `TimeDateWidget.qml` to preserve the current calendar area, account for a small inter-button gap in `targetWidth`, and instantiate `WorldClockButton` as a visually separate sibling. Register the local component in `bar/modules/qmldir`.
- [x] Implement `WorldClockButton.qml` with the bar's `IconButton` dimensions/animations, a globe Nerd Font icon, `ThemeBackend` hover/active colors, `FileView` tracking of `current_widget`, and `toggle worldclock` launch.
- [x] Add a `worldclock` launcher/layout entry in `WindowRegistry.js` (approximately `1180×640`, top/bottom centered just beyond the bar, centered for side bars) and add `worldclock` to `Main.qml`'s preload list. Rely on existing generic IPC and popup lifecycle.
- [x] Implement `world_clock.py` with strict JSON input/output, local-zone detection, `ZoneInfo` validation, current time/date/abbreviation/UTC offset/day delta for all selected zones, and a searchable catalog parsed from tzdata's `zone1970.tab` coordinates.
- [x] Build `WorldClockPopup.qml`: cards show label, time, date, abbreviation/offset, today/±day badge, and day/night state; edit mode supports search/add, remove, move up/down, reset defaults, and a 12/24-hour override. Save the full top-level object with `Config.setSetting` and debounce writes.
- [x] Add graceful fallbacks: reject invalid/missing IANA zones without breaking the popup, show an inline helper error with last good data, cap selected regions, and keep a styled static panel background behind the 3D view if Qt Quick 3D content is unavailable.
- [x] Keep the upstream patch surface explicit and documented so a future Serpantinum revision fails during build rather than silently dropping the button or popup.

## Verification

- [x] Run `nix-instantiate --parse modules/desktop/serpantinum.nix` and Python syntax checks for `patch-serpantinum.py` / `world_clock.py`.
- [x] Run the patcher against a copy of pinned Serpantinum `26e40a3`; verify it changes the intended four upstream files and rejects a second run rather than double-patching.
- [x] Build the configured Serpantinum package from `nixosConfigurations.nixos.config.home-manager.users.surya.programs.serpantinum.package` without switching; the build resolved the QtQuick3D overlay and completed successfully.
- [x] Unit-test the helper with valid zones plus an invalid ID; the environment lacks `/usr/share/zoneinfo/zone1970.tab`, so coordinate catalog results require the packaged Nix `tzdata` path and were not asserted locally.
- QML runtime/UI smoke testing remains pending until the user switches the configuration; the package build and flake evaluation do not prove live Quickshell rendering.
- When explicitly authorized, run `nh os switch`, then restart the current official-module unit with `systemctl --user restart serpantinum` and inspect `journalctl --user -u serpantinum`; do not claim a live smoke test unless this was actually done.
- Confirm the existing clock still opens Calendar; the separate globe button opens/closes World Clock; outside-click and Escape close it; the active button state follows `current_widget`; and all bar styles/positions/scales remain usable.
- Add, remove, reorder, reset, and change 12/24-hour mode; restart Quickshell and switch again to prove UI state persists and Nix seeding does not overwrite it.
- Validate globe drag, bounded zoom, card/marker focus, city positions, selected pulse, and approximate day/night terminator at several UTC times and around the International Date Line.
- Measure the closed-state and open-idle CPU/GPU usage; confirm no helper processes or globe animations continue while hidden and interaction remains smooth on the 3440×1440 display.
- Confirm the repository-owned schematic texture and `ASSET-SOURCES.md` ship together and that the feature performs no runtime network requests.
