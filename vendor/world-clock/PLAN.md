# World Clock Top-Bar Module Plan

## Context

Build a native **Serpantinum 2.1.0 / Quickshell** world-clock module inspired by [`olivoil/omarchy-world-clock`](https://github.com/olivoil/omarchy-world-clock). The active Nix input is pinned at Serpantinum revision `44d33831ab6314e7d2d7f0323c1fc023cb08804c`; its horizontal top bar already has a drag-and-drop module picker. The new `worldclock` entry must be available there without being enabled by default, show a globe icon plus the machine's local time when collapsed, and open through Serpantinum's normal master popup when clicked.

The implementation will live in this standalone project and be composed into the existing package override in `/home/surya/Dotfiles/nixos-config/modules/desktop/serpantinum.nix`. This avoids modifying the immutable Nix-store package or maintaining a complete Serpantinum fork.

Confirmed product choices:
- Configurable saved cities, managed from a dedicated **World Clock** page in Serpantinum Settings.
- Offline major-city/IANA-timezone search first, with an Open-Meteo geocoding fallback when the local catalogue has no match.
- World times only in v1: no weather, time conversion, groups, or pinned remote clocks in the collapsed bar.
- A dark satellite-textured 3D Earth with current sunlight/day-night shading.
- Continuous smooth auto-rotation; dragging takes control, carries inertia, then eases back to idle rotation.

## Architecture

### Native shell integration

- Expose a Nix `patchSerpantinum` helper that appends to the existing `overrideAttrs` pipeline, copies this project's QML/backend/assets into `$out/share/serpantinum`, and applies fail-closed patches against the pinned 2.1.0 source layout.
- Register `worldclock` in `guide/BarTab.qml`'s module metadata, icon/color maps, available-module list, and labels so it can be dragged into any bar section or group.
- Add `WorldClockWidget.qml` by following `TimeDateWidget.qml` for sizing, modular/solid/fill styling, group behavior, startup transitions, and `qs_manager.sh toggle worldclock`. The bar text remains the machine-local `DateTime.timeOnly`, so no helper process runs while only the collapsed widget is visible.
- Register `worldclock` in `WindowRegistry.js`, `Main.qml`, and the cached popup flow. `WorldClockPanel.qml` will inherit the existing overlay's morph transition, outside-click handling, repeated-click toggle, Escape handling, and top/bottom/side-bar positioning.
- Add a top-level `{ id: "WorldClock", key: "world_clock", ... }` entry to `guide/GuidePopup.qml` and a dedicated `guide/worldclock/WorldClockTab.qml`. The panel's settings button deep-links to this tab; city editing does not clutter the expanded clock panel.

### Configuration and time service

Persist one versioned top-level Serpantinum setting via `Config.getSetting("worldClock", ...)` / `Config.setSetting("worldClock", ...)`:

```json
{
  "version": 1,
  "timeFormat": "bar",
  "onlineSearch": true,
  "globe": { "autoRotate": true, "rotationSpeed": 2.5 },
  "cities": [
    {
      "id": "stable-id",
      "place": "Bengaluru",
      "label": "Bengaluru",
      "timezone": "Asia/Kolkata",
      "latitude": 12.97623,
      "longitude": 77.60329
    }
  ]
}
```

- Keep module placement solely in `bar.modules`; do not duplicate an `enabled` flag in `worldClock`.
- On first use, derive the home entry from `general.location` when it has a valid city/timezone/coordinate, then seed a small set of global cities. If no location is available, seed UTC plus global defaults. Do not overwrite an existing user list.
- Normalize malformed/old data, preserve unknown fields, reject invalid coordinates/zone IDs, and migrate the earlier `regions`/`hour12`/`globe.idleRotation` shape if it is ever restored from backup.
- Add `WorldClockService.qml` as a shared singleton for normalized settings, immutable city-list updates, debounced search, subprocess lifecycle, snapshots, error state, and minute-aligned refreshes.
- QML's JavaScript runtime cannot reliably format arbitrary IANA zones. Build a small stateless Rust helper using `chrono`/`chrono-tz` that accepts the configured city array and returns one JSON snapshot with DST-correct time, date, day delta, abbreviation, and UTC offset for every city. Run it on panel activation, settings changes, and minute boundaries only.
- The helper's `search` command searches the bundled Natural Earth major-city catalogue and IANA aliases locally. Only when local results are empty, the query is at least two characters, and `onlineSearch` is enabled does it call Open-Meteo's geocoding endpoint. Tag online results in the UI, debounce input, ignore stale responses, and degrade to a clear offline/no-results state on timeout or failure.
- Settings provides search/add, optional personal labels, remove, drag-or-button reorder, time format (`Follow bar`, `12-hour`, `24-hour`), online-search toggle, auto-rotate toggle, and rotation speed. All writes go through Serpantinum's existing atomic JSON update path.

### Globe and expanded panel

- Use `QtQuick3D`'s built-in sphere geometry with NASA/public-domain day and night satellite textures, a cloud layer, and a subtle larger atmosphere shell. Pin source URLs/checksums and ship attribution/provenance. These are static surface/cloud textures; only the sunlight position and clocks are live.
- Compile a Qt Quick 3D custom material with `qsb` during the Nix build. Blend day imagery and night lights across a soft terminator, retain restrained ocean/specular response, and render an atmosphere Fresnel/rim so the result stays dark but legible.
- Compute the current solar declination/subsolar longitude from UTC in QML, update it once per minute, and rotate the light with the presentation node. This preserves the real geographic day/night boundary while the globe rotates for viewing.
- Keep geographic Earth coordinates immutable and rotate a parent presentation node containing Earth, lighting, and markers. Convert saved latitude/longitude to sphere vectors, project marker anchors through `View3D.mapFrom3DScene`, hide back-hemisphere labels, and resolve front-side label overlap deterministically.
- Show the globe as the visual focus with a right-hand list of saved city cards. Each card shows place/custom label, current local time, local date/day difference, and timezone abbreviation. Selecting a card smoothly rotates the globe toward that marker; selecting a marker highlights the card.
- Implement drag yaw/pitch with a pitch clamp, velocity sampling, inertial decay, and a timed eased blend back to configured idle speed. Pause the frame driver while the panel is inactive and stop minute/search work when neither the panel nor Settings page needs it.
- Include a friendly empty state and a gear action that opens Settings → World Clock. Do not add city editing, weather, or time conversion to the panel in v1.

## Files

### New standalone project files

- `flake.nix`, `default.nix` — backend package, shader compilation, checks, and the reusable Serpantinum package transformer.
- `Cargo.toml`, `Cargo.lock`, `src/main.rs`, `src/time.rs`, `src/catalog.rs`, `src/open_meteo.rs` — stateless snapshot/search helper and fixture-testable Open-Meteo parsing.
- `qml/bar/modules/WorldClockWidget.qml` — collapsed globe/local-time bar item.
- `qml/worldclock/WorldClockPanel.qml` — expanded panel composition and lifecycle.
- `qml/worldclock/WorldClockGlobe.qml` — Qt Quick 3D scene, projection, lighting, drag/inertia/resume.
- `qml/worldclock/WorldClockCityList.qml` — saved-city cards and panel selection synchronization.
- `qml/guide/worldclock/WorldClockTab.qml` — dedicated Settings editor/search UI.
- `qml/singletons/WorldClockService.qml` — config schema/migration, service state, processes, refresh scheduling.
- `qml/worldclock/WorldClockMath.js` — pure geographic projection and solar-position math.
- `data/featured-cities.json`, `data/timezone-grid.bin`, `data/ODbL-1.0.txt` — offline city search and coordinate-to-timezone lookup, derived from the upstream MIT project's documented Natural Earth/tzf-rel pipeline.
- `assets/earth-day.*`, `assets/earth-night.*`, `assets/earth-clouds.*`, `assets/shaders/*` — pinned Earth imagery and source/compiled shaders.
- `scripts/patch_serpantinum.py` — idempotent exact-anchor patcher with Serpantinum version/revision expectations.
- `tests/` — Rust DST/search/network-fixture tests, pure JS/QML math tests, patch fixtures, and a QtQuick3D smoke scene.
- `README.md`, `LICENSE`, `LICENSES.md` — installation, architecture, controls, privacy behavior, and all reused data/code/image notices.

### Existing Nix configuration

- `/home/surya/Dotfiles/nixos-config/flake.nix` and `flake.lock` — add/lock the local `world-clock` flake input following the existing `nixpkgs`.
- `/home/surya/Dotfiles/nixos-config/modules/desktop/serpantinum.nix` — apply `world-clock.lib.patchSerpantinum` to the already Bluetooth-patched Serpantinum derivation, preserving the current fix and settings.

### Serpantinum files patched in the package output

- `quickshell/guide/BarTab.qml` — module metadata and available-module registration.
- `quickshell/guide/GuidePopup.qml` — dedicated Settings sidebar entry/page loader.
- `quickshell/bar/TopBar.qml` — world-clock width lookup, layout/group calculations, lookup API, and widget instance.
- `quickshell/WindowRegistry.js` — popup metadata, dimensions, and bar-position anchoring.
- `quickshell/Main.qml` — popup preload/cache registration.
- `assets/languages/en.json` — Settings tab, module, editor, empty/error, and privacy labels; other locales use existing English fallback.

## Reuse

- `bar/modules/TimeDateWidget.qml` for the collapsed bar contract and `guide/BarTab.qml` for drag/drop module placement.
- `Main.qml` and `WindowRegistry.js` for popup caching, transitions, positioning, outside-click, and Escape behavior.
- `singletons/Config.qml`, `DateTime.timeOnly`, `ThemeBackend`, `Scaler`, and existing reusable controls for persistence, local time, theme, scale, and visual consistency.
- Installed Qt 6.11.2 `QtQuick3D`/`qtshadertools`; the current Serpantinum wrapper already exposes the QtQuick3D import path.
- The upstream project's MIT backend concepts and documented Natural Earth/tzf-rel datasets where useful, while keeping this v1 helper stateless and omitting upstream weather/converter/group/config-file features.

## Implementation steps

- [x] Scaffold the flake, Rust helper, vendored data/licenses, QML layout, shader build, and checks.
- [x] Implement the exact-anchor patcher and assert the pinned Serpantinum 2.1.0 version/revision before changing output files.
- [x] Add `worldclock` to Bar Settings, TopBar layout/group APIs, popup registry/cache, and English translations.
- [x] Implement the collapsed globe/local-time widget and verify all bar styles, sections, and groups.
- [x] Implement the versioned `worldClock` schema, defaults from `general.location`, legacy normalization, immutable updates, and shared service state.
- [x] Implement/test DST-aware snapshots, offline ranked city/IANA search, and opt-out Open-Meteo fallback with cancellation/stale-result protection.
- [x] Build the dedicated Settings page for search/add/label/remove/reorder and display/motion preferences.
- [x] Build the expanded native panel and city list with empty, loading, partial-error, and backend-unavailable states.
- [x] Build the 3D Earth shaders, live solar calculation, markers, label collision handling, selection focus, drag inertia, smooth auto-spin resumption, and inactive throttling.
- [x] Compose the package transformer with the current Bluetooth override in `nixos-config`, build it, activate the Home Manager generation, and restart the Serpantinum user service.

## Verification

- Run `cargo fmt --check`, `cargo clippy -- -D warnings`, and unit/integration tests. Cover New York summer/winter DST, Kolkata's fixed offset, midnight/date-line day deltas, invalid zones/coordinates, ranked local search, Open-Meteo fixtures, timeout/error parsing, and no-network behavior when disabled.
- Run Nix formatter/evaluation and flake checks; build both the helper and full patched Serpantinum derivation without mutating the live profile first.
- Test patching against the pinned source, unsupported-version failure, missing-anchor failure, and second-pass idempotence/clean recognition.
- Run `qmllint` with Serpantinum/Quickshell import paths, pure math tests for known lat/lon and equinox/solstice cases, and a Mesa/offscreen QtQuick3D shader/import smoke test.
- In Settings → Bar, drag World Clock into/out of left, center, right, and a group; verify layout width, hover/style behavior, persistence, and no change to the default module layout.
- In Settings → World Clock, add via local and Open-Meteo results, rename, reorder, remove, toggle online search, change format/motion preferences, restart Serpantinum, and verify unrelated settings remain byte-semantically intact.
- Compare displayed times with system `date`/`zdump` around DST transitions and across midnight; confirm a backend/network failure leaves the shell responsive and existing clocks visible with an explicit error state.
- Verify the popup opens/closes via click, repeated click, outside click, and Escape; the gear deep-link opens the dedicated page; no duplicate popup is created.
- Visually verify recognizable Earth orientation, current terminator position, front/back marker visibility, label collision handling, click-to-focus, drag direction, inertia, eased resume, scaling, and dark-theme contrast.
- Confirm the frame driver and minute timer stop when the panel is closed, no online requests occur except explicit city searches after local miss, and idle Serpantinum CPU/GPU usage returns to baseline.
