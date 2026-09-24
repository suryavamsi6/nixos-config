# MangoWM Scrolling Tags System Plan

## Context

Create a second, optional `x86_64-linux` NixOS system configuration for experimenting with MangoWM while preserving the existing Hyprland system. The target is a scrolling/tag-oriented workflow first, with the current shell, Serpantinum/Quickshell desktop UI, hardware integrations, and gaming stack carried over where they are compositor-independent.

Current repository findings:

- `modules/hosts/nixos-hyprland.nix` is the primary `#nixos` host and composes hardware, core services, `nixos.hyprland`, `nixos.serpantinum`, gaming, work, and Home Manager imports.
- `modules/hyprland/wm.nix` contains both the NixOS compositor/session setup and the Home Manager Hyprland Lua wiring; Lua lives in `modules/hyprland/lua/`.
- `modules/desktop/serpantinum.nix` owns the patched Serpantinum package and user-service integration; the UI itself is not inherently Hyprland-specific, but its launcher/autostart hooks and portal/window rules need an audit.
- `modules/packages/gaming.nix` is already a shared gaming module with Steam, Gamescope, GameMode, MangoHud, Mangojuice, and related packages.
- The working tree already contains unrelated staged/unstaged changes, including the recent gridwatch work. The implementation must avoid overwriting or conflating those changes.
- Linear MCP was unavailable through the generic MCP gateway, but the requested `/orca-linear` route is available. Eight durable Linear issues were created in the `SUR` team (`SUR-5` through `SUR-12`) with feature labels and blocking relations; no Linear project container was created because the available CLI exposes issue/task creation but not Linear project creation.
- Pinned nixpkgs audit is complete: `programs.mango.enable` and `programs.mango.package` exist; pinned `pkgs.mango` is version `0.16.2`. The nixpkgs module supplies the package, WLR/GTK portal configuration, `services.displayManager.sessionPackages`, and `xdg.portal`; it does not itself enable XWayland or polkit. Pinned Home Manager has no Mango module, so the repository will provide a small deferred HM module that writes `~/.config/mango/config.conf`, validates it with `mango -p`, and starts the session target/autostart path.

## Approach

1. Add MangoWM as a separate compositor module rather than replacing Hyprland. Keep shared system, shell, hardware, audio, wallpaper, work, gaming, and gridwatch modules reusable.
2. Add a distinct `#mango` flake host output using the same physical machine hardware modules but a separate experimental hostname/session path; leave the existing `#nixos` Hyprland output unchanged.
3. Use the current pinned nixpkgs package/module (`programs.mango` and the corresponding Home Manager MangoWM option if present) rather than adding a new MangoWM flake input. Verify the pinned nixpkgs revision exposes the required scroller/tag features before implementation.
4. Port behavior in layers: compositor/session bootstrap; scrolling layout and hybrid numeric/semantic tags; keyboard/input/monitor policy; Serpantinum launch and `mmsg` IPC; status/OSD/notifications/idle/polkit; screenshots and utilities; then gaming-specific behavior.
5. Prefer MangoWM’s native config and `mmsg` IPC/watch streams over attempting to translate Hyprland Lua mechanically. Keep compositor-neutral commands and compatibility scripts small and shared.
6. Treat the first milestone as a safe, reversible trial: no rebuild/switch until explicitly authorized, and no removal of Hyprland wiring.

## Files to modify

Planned paths (to confirm after inspecting the pinned nixpkgs options/API):

- `modules/mangowm/default.nix` and `modules/mangowm/wm.nix` for deferred NixOS/Home Manager MangoWM modules.
- `modules/mangowm/config/` or equivalent for MangoWM config, scrolling layout, tags, rules, monitors, and bindings.
- `modules/hosts/nixos-mango.nix` for the separate `#mango` host composition.
- `modules/hosts/default.nix` only if host auto-registration needs an explicit entry.
- `modules/desktop/greetd.nix` or a new session module for selectable MangoWM startup, without changing the current Hyprland default unexpectedly.
- `modules/desktop/serpantinum.nix` only for compositor-neutral startup/portal/window-rule assumptions discovered during audit.
- `modules/packages/gaming.nix` only if its current idle integration assumes `hypridle`; prefer a generic idle service contract rather than duplicating the gaming stack.
- Shared shell/environment/package modules only when a current Hyprland-specific dependency is found.
- `AGENTS.md` or repository docs only if the final operating procedure needs documenting.

Planning is complete; implementation and validation are tracked below.

## Reuse

- Reuse host module composition from `modules/hosts/nixos-hyprland.nix`, but make MangoWM-specific desktop imports explicit and keep the same physical hardware/NVIDIA/OpenRGB/gridwatch/audio/networking stack.
- Reuse shared modules: `nixos.hardwareHyprland`, `nixos.nvidia`, `nixos.gcb200`, `nixos.openrgb`, `nixos.gridwatch`, boot, nix settings, users, networking, environment, shell, fonts, audio, greetd, gaming, social, system, work, Hermes, locale.
- Reuse Home Manager imports: `homeManager.shell`, `wallpapers`, `dev`, `work`, `gaming`, and `gridwatch`. Preserve Fish, Ghostty, Starship, Matugen, browsers, work wrappers, and credentials/session behavior.
- Reuse Serpantinum packaging, UPS additions, wallpaper assets, `swayosd`, standalone idle/lock/polkit services, screenshot tools, clipboard watchers, and existing watcher/cache flow wherever they do not depend on Hyprland IPC.
- Port the intent of `modules/hyprland/lua/{vars,monitors,input,binds,rules,autostart,look,animations}.lua`; do not copy Hyprland-only APIs. Current behavior includes HDMI-A-2/HDMI-A-1 3440x1440@175 HDR, Super bindings for launcher/settings/apps, focus/move/float/fullscreen, scratchpad, numeric workspaces 1–0, media/brightness, screenshots, lock, clipboard, wallpaper/network/volume/calendar/focus-time panels, and clipboard/player/Bluetooth/background daemons.
- MangoWM provides `scroller` and `vertical_scroller`, per-tag layouts/tag rules, hot reload, XWayland, and `mmsg` JSON get/watch commands for tags, clients, monitors, and devices. Use `mmsg watch all-tags`/monitor state for Serpantinum integration where needed.
- Preserve `modules/packages/gaming.nix` as the source of truth for Steam/Gamescope/GameMode/MangoHud instead of creating a second gaming package list. Replace only its Hyprland-specific `hypridle` start/stop hooks if the MangoWM module uses a generic idle service.

## Steps

- [x] Confirm the pinned nixpkgs MangoWM package/module and exact options: `programs.mango.enable`, `programs.mango.package`, `services.displayManager.sessionPackages`, WLR/GTK portal routing, and package `0.16.2`. Pinned HM has no Mango module; use the upstream 0.16.2 config syntax (`settings`/`extraConfig` equivalent), `~/.config/mango/config.conf`, `scroller`/`vertical_scroller`, `tagrule`, monitor/input options, hot reload, and `mmsg get/watch` commands.
- [x] Create the Linear task sequence with acceptance criteria and blocking relations so work survives reboot and can be resumed safely (`SUR-5` through `SUR-12`).
- [x] Decide and document the `#mango` output name/hostname and recovery path. Reuse the current hardware modules but ensure the display manager can select Hyprland or MangoWM without making an untested Mango session the default.
- [x] Define the first hybrid tag UX: retain Super+1…9 for numeric tags, reserve a documented semantic convention (code/web/chat/media/game/work/files/misc/staging), and keep semantic labels as aliases in the first trial.
- [x] Define the dwindle baseline for every tag with gaps/borders, monitor rules, focus/move/resize/fullscreen/floating commands, and escape/recovery bindings.
- [x] Implement a deferred MangoWM NixOS module using the current nixpkgs integration: enable the compositor, install runtime utilities, configure XWayland and the Mango-compatible portal stack, enable polkit/desktop prerequisites, and expose a clean login entry.
- [x] Implement a Home Manager MangoWM module with native config generation and `mango -p` validation, keyboard layout/input, HDMI-A-2/HDMI-A-1 monitor setup, scrolling/tag rules, focus/move/resize/fullscreen/floating commands, environment variables, pointer cursor, autostart, idle, and polkit services.
- [x] Add `modules/hosts/nixos-mango.nix` by composing shared hardware/core/package modules and swapping only the Hyprland-specific desktop layer for MangoWM. Keep `#nixos` available as the default rollback host.
- [x] Add or adapt greetd session enumeration so `mango` is selectable and the existing `start-hyprland` remembered-session behavior is not broken. Validate generated session files/commands before any switch.
- [x] Port Serpantinum startup and UI controls: systemd startup, quickshell QML path, launcher/settings/clipboard/wallpaper/network/volume/calendar/focus-time panels, UPS controls, Bluetooth widgets, Matugen updates, and bar visibility. Add focused Mango `mmsg` patches for workspace, keyboard-layout, and monitor-power paths while preserving watcher/cache flow.
- [x] Port the remaining desktop affordances: `swayosd` media/brightness keys, notifications, idle locking, polkit authentication, screenshots, clipboard, screen capture, terminal/browser bindings, and floating rules for dialogs/tool windows. Replace `hypridle`/`hyprlock`/`hyprpolkitagent` assumptions with Mango-compatible components where necessary.
- [x] Add gaming readiness wiring: preserve Steam/Gamescope/GameMode/MangoHud/Proton packages and make GameMode stop/start the actual Mango idle service alongside the existing Hyprland idle service. Runtime gaming checks remain part of acceptance validation.
- [x] Add documentation/runbook details for selecting `#mango`, selecting the session at greetd, reverting to Hyprland, collecting Mango/mmsg/Quickshell logs, and known Mango/Serpantinum/NVIDIA limitations.
- [x] Validate with focused Nix parsing/evaluation and a non-switch build/check where practical; only perform `nixos-rebuild`/runtime UI checks after explicit authorization.

Validation note: focused Nix parsing/evaluation and the current-tree non-switch Mango build pass. The unused `#plasma` host was later removed so it no longer blocks flake evaluation.
## Verification

- Parse every new/changed Nix file with `nix-instantiate --parse`.
- Evaluate both the existing `.#nixos` output and the new MangoWM output without switching; verify no Hyprland output regressions and no missing module options.
- Confirm the generated Wayland session is present and the MangoWM command starts with the expected environment.
- Manual trial checklist: login/recovery; scrolling layout; tag creation/focus/move; multi-monitor behavior; launcher and Serpantinum overlays; UPS/status widgets; Bluetooth; audio/brightness OSD; screenshots; idle/polkit; XWayland apps; Steam; Gamescope; a representative game; suspend/logout back to the display manager.
- Verify Hyprland remains selectable and that reverting the MangoWM host/session requires no destructive changes.
- Do not claim a rebuild, switch, or runtime smoke test unless it is actually run.

## Linear task outline and created issues

The durable task sequence is recorded in Linear under the `SUR` team. Issues are Todo, labeled Feature, and linked with blocking relations:

1. [SUR-5 — Audit pinned nixpkgs MangoWM support](https://linear.app/suryavamsi/issue/SUR-5/mangowm-trial-audit-pinned-nixpkgs-mangowm-support) — compatibility matrix and explicit blockers.
2. [SUR-6 — Add the #mango host skeleton](https://linear.app/suryavamsi/issue/SUR-6/mangowm-trial-add-the-mango-host-skeleton) — shared stack, separate output, no changes to existing hosts.
3. [SUR-7 — Wire selectable MangoWM login session](https://linear.app/suryavamsi/issue/SUR-7/mangowm-trial-wire-selectable-mangowm-login-session) — greetd/session generation and rollback.
4. [SUR-8 — Implement scrolling layout and hybrid tags](https://linear.app/suryavamsi/issue/SUR-8/mangowm-trial-implement-scrolling-layout-and-hybrid-tags) — scroller, vertical alternative, numeric tags, semantic aliases, keymap.
5. [SUR-9 — Port compositor-independent desktop services](https://linear.app/suryavamsi/issue/SUR-9/mangowm-trial-port-compositor-independent-desktop-services) — startup/stop paths for shell and desktop utilities.
6. [SUR-10 — Port Serpantinum and Quickshell integration](https://linear.app/suryavamsi/issue/SUR-10/mangowm-trial-port-serpantinum-and-quickshell-integration) — `mmsg` integration, overlays, UPS/Bluetooth, watcher/cache preservation.
7. [SUR-11 — Make gaming ready on MangoWM](https://linear.app/suryavamsi/issue/SUR-11/mangowm-trial-make-gaming-ready-on-mangowm) — Steam/Gamescope/GameMode/MangoHud, NVIDIA, XWayland, VRR, capture, controllers, audio.
8. [SUR-12 — Document trial, rollback, and acceptance](https://linear.app/suryavamsi/issue/SUR-12/mangowm-trial-document-trial-rollback-and-acceptance) — build/session commands, logs, recovery, limitations, final checklist.

Dependencies recorded: `SUR-5` blocks `SUR-6` and `SUR-7`; `SUR-6` blocks `SUR-7` and `SUR-8`; `SUR-7` blocks `SUR-8`; `SUR-8` and `SUR-9` block `SUR-10` and `SUR-11`; `SUR-10` blocks `SUR-11`; `SUR-11` blocks `SUR-12`.
