# Controlled CachyOS Kernel Trial

## Decision

Trial Chaotic-Nyx `pkgs.linuxPackages_cachyos` on the primary `#nixos` Hyprland host, with the stock nixpkgs kernel available in the same generation as a Limine specialisation.

The trial configuration is:

- Primary kernel: CachyOS default `7.2.2` build (EEVDF, 1000 Hz, `PREEMPT_DYNAMIC`, Clang ThinLTO, AutoFDO/Propeller).
- NVIDIA: the Chaotic-Nyx matching open `config.boot.kernelPackages.nvidiaPackages.cachyos`, currently `610.57.04`, because nixpkgs production `595.99.02` cannot build against the cached CachyOS development tree (missing module-signing key).
- Boot fallback: stock nixpkgs `pkgs.linuxPackages`, currently `6.18.48`, as `specialisation.stock-kernel`.
- Scope: `nixosConfigurations.nixos` only. `nixosConfigurations.plasma` remains on stock `6.18.48` and its existing NVIDIA beta package.
- Scheduler: leave the in-kernel EEVDF scheduler active. Do not enable an SCX userspace scheduler during this trial.

Keep CachyOS only if every applicable functional gate passes and controlled A/B measurements show a meaningful frame-time improvement. If the results are within run-to-run noise, stock remains the preferred kernel because it has the lowest support and upgrade risk.

## Why this is the recommended trial

- The workstation is a Ryzen 7 9800X3D, RTX 5080, RTL8125 Ethernet, and MT7922 Wi-Fi/Bluetooth system. All of those devices use upstream or NVIDIA-supported drivers with both candidate kernels.
- CachyOS's default kernel is the most defensible gaming-focused candidate: it is the project's recommended default and retains upstream EEVDF rather than adding a second scheduler experiment.
- Current independent benchmark evidence does not demonstrate a consistent gaming win over stock Linux. The recommendation is therefore an experiment with explicit rejection criteria, not a claim that CachyOS is universally faster.
- The current stock kernel is already strong: Linux `6.18.48`, 1000 Hz, and dynamic preemption. Large gains are not expected.
- The existing Chaotic-Nyx module and cache are already present on `#nixos`; no flake input or lock-file change is needed.
- The final configuration evaluates to CachyOS `7.2.2` plus NVIDIA `610.57.04`, and stock `6.18.48` plus production NVIDIA `595.99.02` in the specialisation. The first real build with production `595.99.02` failed at NVIDIA module signing; the matching Chaotic prebuilt driver then built successfully.
- Limine's NixOS module emits BootSpec specialisations as bootable entries. The existing Secure Boot setup and ten retained generations remain the recovery foundation.
- `/boot` currently has about 941 MiB free (82 MiB used of 1022 MiB), so the additional kernel/initrd has ample initial headroom. Capacity is still checked after installation.

## Alternatives considered

- **Remain on stock `linuxPackages`:** safest production choice and the baseline/fallback. Select this permanently if the trial is neutral or regresses.
- **`linuxPackages_latest`:** currently the same upstream `7.2.2` line without the CachyOS gaming-oriented build; it adds kernel churn without testing the proposed optimization set.
- **`linuxPackages_zen`:** currently `7.1.10`; the 7.1 upstream branch is end-of-life, so it is unsuitable for a stability-sensitive workstation.
- **`linuxPackages_cachyos-lts`:** currently based on `6.18.48`; useful for conservative CachyOS patch testing, but it does not test the default current CachyOS gaming kernel selected by the user.
- **BORE/BMQ/other scheduler variants:** not selected because CachyOS recommends the default kernel and available evidence does not establish a repeatable gaming advantage.
- **SCX schedulers (`scx_lavd`, `scx_rustland`, and others):** deliberately deferred. Adding a userspace scheduler would confound the kernel A/B comparison and repeat a prior unmeasured experiment.
- **`linuxPackages_cachyos-lto-znver4`:** compatible with Zen 4/5 according to CachyOS, but deferred to a separate second experiment. It narrows CPU portability and adds another variable while reported gains are generally small. The default kernel is the safer first trial.
- **Chaotic `nvidia_cachyos` / NVIDIA 610:** initially rejected as unnecessary driver-version risk, but now required for this trial because it is the only available matching prebuilt NVIDIA module after production `595.99.02` failed to build against CachyOS. Treat NVIDIA `610.57.04` as an additional trial variable and reject on any driver regression.

## Scope and non-goals

### In scope

- Add the CachyOS kernel, matching Chaotic NVIDIA override, trial tag, and stock-kernel specialisation to `#nixos` only.
- Preserve `nvidia_uvm` loading and all existing NVIDIA DRM/open-module settings.
- Build and install both kernels as one Limine generation; Secure Boot signs the Limine EFI loader, while Limine's enrolled configuration checksums protect the loaded kernel files.
- Benchmark stock and CachyOS with the same userspace generation while recording the NVIDIA driver difference as a confounding variable.
- Exercise Hyprland, NVIDIA display/DPMS, CUDA Ollama, Citrix/Zoom VDI, gaming, networking, audio/Bluetooth, and any actually configured container runtime.
- Document the active choice and correct the stale RTL8125 driver note.

### Out of scope

- No flake input or `flake.lock` update.
- No kernel patching or custom kernel derivation.
- No sysctl, CPU governor, SCX, IRQ, scheduler, or GameMode tuning during the kernel comparison.
- No changes to `#plasma`, `#macbook-air`, or Raspberry Pi hosts.
- No new container runtime merely to manufacture a test surface.
- No suspend or power-off test: this desktop is the Hermes worker and must not be suspended or powered off. Reboots required for the kernel A/B are the only lifecycle operations.
- No use of `NIXPKGS_ALLOW_BROKEN=1` or other overrides to force a broken closure.

## Files and exact configuration design

### `modules/hosts/nixos-hyprland.nix`

Extend the existing host-specific inline module rather than the shared hardware module. Change its arguments from `{ pkgs, ... }` to `{ config, lib, pkgs, ... }`, then add the equivalent of:

```nix
boot.kernelPackages = pkgs.linuxPackages_cachyos;
hardware.nvidia.package =
  lib.mkForce pkgs.linuxPackages_cachyos.nvidiaPackages.cachyos;

system.nixos.tags = [ "cachyos-trial" ];

specialisation.stock-kernel.configuration = { lib, pkgs, ... }: {
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages;
  hardware.nvidia.package = lib.mkOverride 10 pkgs.linuxPackages.nvidiaPackages.production;
  system.nixos.tags = lib.mkForce [ "stock-kernel" ];
};
```

Why here:

- The Chaotic-Nyx module is imported by `#nixos` but not by `#plasma`.
- `modules/hardware/nvidia.nix` and `modules/hardware/hyprland-hw.nix` are shared by both Linux hosts.
- A host-local override avoids unintentionally moving `#plasma` to CachyOS or changing its NVIDIA branch.
- The parent trial driver is pinned to the Chaotic CachyOS package, while the specialisation uses an explicit lower-priority override for stock production NVIDIA. This avoids re-evaluating a CachyOS-only package in the stock package set.

### `README.md`

- Replace the stale statement that RTL8125 requires out-of-tree `r8125`. Current configuration and live PCI state use in-tree `r8169`.
- Add a concise kernel/rollback note: `#nixos` is under a controlled CachyOS trial, `stock-kernel` is available under the newest Limine generation, and previous generations remain available.
- State that a kernel change must be installed with `nixos-rebuild boot` and selected after reboot; runtime specialisation switching cannot replace a running kernel.
- If the trial is rejected, remove the temporary CachyOS trial note but retain the corrected `r8169` documentation.

### Files deliberately unchanged

- `modules/hardware/nvidia.nix`: retain `open = true`, DRM modesetting, and `boot.kernelModules = [ "nvidia_uvm" ]`; the package override is host-local.
- `modules/boot/default.nix`: retain Limine Secure Boot, `maxGenerations = 10`, and the existing menu configuration. Verify generated entries rather than assuming numeric menu positions.
- `flake.nix` and `flake.lock`: Chaotic-Nyx is already integrated and pinned.

## Preserve unrelated work

The tree already contains many unrelated modifications, including the target host and NVIDIA files. During implementation:

1. Record `git status --short` and focused diffs for `modules/hosts/nixos-hyprland.nix`, `modules/hardware/nvidia.nix`, `modules/boot/default.nix`, and `README.md` before editing.
2. Patch only the host-specific inline block and the documented README lines.
3. Do not reset, checkout, stage, reformat, or rewrite unrelated files.
4. Re-read the final focused diff and prove that `modules/hardware/nvidia.nix`, `modules/boot/default.nix`, `flake.nix`, and `flake.lock` were not changed by this work.

## Implementation sequence

### 1. Capture the pre-trial reference

Create a timestamped evidence directory outside the repository, for example `~/kernel-trial/2026-09-03/`, and capture:

- Current generation and booted kernel: `readlink -f /run/current-system`, `uname -a`, and system profile generations.
- Secure Boot and boot state: `bootctl status`, `sbctl status`, and current `/boot` free space.
- GPU state: `nvidia-smi`, loaded NVIDIA modules, DRM modeset parameter, and kernel warnings/errors for the current boot.
- Network drivers and links: `lspci -k`, `ethtool` for the wired NIC, Wi-Fi status, and WoL state.
- `systemctl --failed`, relevant user-service failures, `wpctl status`, and the current Hyprland monitor layout.
- Current app build IDs and launch settings for the benchmark games.

This reference detects driver or userspace changes, but it is not the final kernel A/B baseline because it uses NVIDIA beta `595.45.04`.

### 2. Apply the two focused source edits

- Add the host-local kernel, matching Chaotic NVIDIA, and specialisation settings to `modules/hosts/nixos-hyprland.nix`.
- Update the kernel, NVIDIA trial, and RTL8125 documentation in `README.md`.
- Confirm that the final diff contains no unrelated changes.

### 3. Parse and evaluate before building

Run focused syntax and evaluation checks:

```bash
nix-instantiate --parse modules/hosts/nixos-hyprland.nix >/dev/null
nix eval --raw .#nixosConfigurations.nixos.config.boot.kernelPackages.kernel.version
nix eval --raw .#nixosConfigurations.nixos.config.hardware.nvidia.package.version
nix eval --raw '.#nixosConfigurations.nixos.config.specialisation.stock-kernel.configuration.boot.kernelPackages.kernel.version'
nix eval --raw '.#nixosConfigurations.nixos.config.specialisation.stock-kernel.configuration.hardware.nvidia.package.version'
nix eval --raw .#nixosConfigurations.plasma.config.boot.kernelPackages.kernel.version
nix eval --raw .#nixosConfigurations.plasma.config.hardware.nvidia.package.version
```

Expected values at the current lock:

- `#nixos`: kernel `7.2.2`, NVIDIA `610.57.04`.
- `#nixos` `stock-kernel`: kernel `6.18.48`, NVIDIA `595.99.02`.
- `#plasma`: kernel `6.18.48`, NVIDIA beta `595.45.04` (unchanged).

Also evaluate tags and top-level derivation paths so the main and fallback closures are distinct and named `cachyos-trial` and `stock-kernel`.

### 4. Build without activating

Build the complete closure, including the specialisation:

```bash
nix build --no-link .#nixosConfigurations.nixos.config.system.build.toplevel
```

Failure policy:

- Stop on any kernel, NVIDIA-module, Secure Boot, or specialisation build failure.
- If the unrelated `cups-2.4.19` broken-package error reappears, do not allow broken packages. Record the dependency path and resolve that repository state separately; do not mislabel it as a kernel regression.
- Do not proceed from a dry-run alone. A real successful build is required.

### 5. Install as a boot generation, not a live switch

Use:

```bash
sudo nixos-rebuild boot --flake .#nixos
```

Do not use `switch` for the first installation. The command should install the new generation without changing the running userspace or pretending that the running kernel changed.

Before rebooting:

- Recheck `/boot` usage; require at least 200 MiB free after installation.
- Inspect the generated Limine configuration and BootSpec data for both the `cachyos-trial` and `stock-kernel` entries.
- Verify the newest generation and previous known-good generation are both present.
- Run `sudo sbctl verify` and require the Limine EFI loader to be signed. Record unsigned legacy/systemd-boot files and kernel bzImages as expected for this Limine hash-validation design unless the installed nixpkgs revision explicitly signs them; do not manually sign Nix-managed kernel files.
- Record the exact Limine menu labels. Recovery instructions must use labels, not hard-coded entry numbers.

### 6. Boot the stock specialisation first

For the first reboot, manually select `stock-kernel` under the newest generation. This produces the valid baseline: stock `6.18.48` and production NVIDIA `595.99.02`, with exactly the same userspace and configuration that CachyOS will use.

Complete all smoke checks and the benchmark suite below. If the production NVIDIA driver or shared userspace fails on stock, stop before testing CachyOS and return to the previous generation.

### 7. Boot the CachyOS entry

Reboot and select the newest generation's normal `cachyos-trial` entry. Confirm `uname -r` reports `7.2.2` and `nvidia-smi` reports `610.57.04`, then repeat the same smoke checks and benchmark suite.

## Functional acceptance gates

Run each applicable gate once on the stock specialisation and again on CachyOS. Preserve command output and short manual notes in the evidence directory.

### Boot, Secure Boot, and kernel health

- `bootctl status` reports Secure Boot enabled.
- `sbctl verify` reports `/boot/EFI/limine/BOOTX64.EFI` signed. Kernel bzImages may be unsigned because Limine validates their enrolled configuration checksums rather than requiring each bzImage to be an EFI-signed image.
- `systemctl --failed` shows no new failures.
- `journalctl -b -k -p warning..alert` shows no new kernel oops, lockups, filesystem errors, firmware failures, or device regressions compared with stock.
- Rebooting between the two entries consistently reaches the expected kernel.

### NVIDIA, Hyprland, and display recovery

- The open NVIDIA modules for the booted kernel load: `nvidia`, `nvidia_modeset`, `nvidia_drm`, and `nvidia_uvm`.
- `nvidia_drm` modesetting remains enabled and `nvidia-smi` sees the RTX 5080 at trial driver `610.57.04` (stock baseline uses `595.99.02`).
- Hyprland starts normally; all monitors, refresh rates, VRR behavior, input devices, Quickshell, screen capture, and Gamescope operate as on stock.
- Run ten DPMS off/on cycles using the existing Hyprland path. A CachyOS-only black screen, HDMI FRL/EDID failure, NVRM Xid, `CTX SWITCH TIMEOUT`, or GPU reset is an immediate rollback trigger.
- Existing DPMS behavior must be recorded on stock so a pre-existing NVIDIA issue is not falsely attributed to the kernel; CachyOS may not make it worse.

### CUDA Ollama and Hermes worker access

- Confirm `nvidia_uvm` is loaded before inference.
- Query Ollama's `/v1/models` endpoint and run a representative local model prompt.
- Observe the Ollama process in `nvidia-smi`; CPU fallback, missing CUDA devices, or new Ollama/NVIDIA errors fail the gate.
- From the Raspberry Pi, verify the dedicated SSH path and wired-LAN Ollama endpoint still work. Do not expose the service beyond its current LAN policy.

### Citrix Workspace and Zoom VDI

- Verify `/opt/Citrix/ICAClient` and `/usr/lib/zoomvdi-universal-plugin` resolve to the current generation and `wfica -version` works.
- Complete the normal embedded Entra/SAML sign-in and launch one ICA desktop/application.
- Join a Zoom VDI test meeting through Citrix and verify plugin detection, audio output, microphone, and camera/screen-sharing paths that are normally used.
- Authentication, ICA launch, plugin load, or AV regressions fail the trial. Do not change the pinned Zoom VDI package while diagnosing the kernel.

### Gaming

- `gamemoded -t` passes; a running test game reports GameMode active.
- Steam, Proton Experimental, MangoHud, and the configured Gamescope session launch normally.
- Play at least 30 minutes in each benchmark title after its measured runs; watch for stutter, freezes, anti-cheat failure, controller/input loss, NVRM Xids, and application crashes.
- A reproducible CachyOS-only crash or compatibility failure is an immediate rejection regardless of FPS.

### Audio and Bluetooth

- `wpctl status` shows the expected PipeWire devices and profile.
- Use the existing BlueZ `busctl` helper path, never `bluetoothctl`, to verify the known headset and A2DP profile.
- Play game audio for at least 30 minutes and verify no crackling, dropouts, profile switching, or sustained PipeWire xruns. Bluetooth remains A2DP-only.

### Ethernet, Wi-Fi, and WoL

- `lspci -k` binds RTL8125 to in-tree `r8169` and MT7922 to the expected MediaTek driver.
- Wired and Wi-Fi links reconnect normally; DNS and sustained LAN transfer behavior are no worse than stock.
- `ethtool` retains the intended wake-on-LAN state and the Raspberry Pi can reach the desktop over the wired LAN after each reboot.

### Containers

Current inspection found no `podman`, `docker`, or `virsh` command installed/configured on this desktop. Therefore:

- Recheck at trial time in case the runtime is supplied outside this repository.
- If a runtime exists, build an image, run a networked container, mount a volume, and stop/remove it on both kernels.
- If none exists, mark the gate explicitly **not applicable**; do not claim it passed and do not add a runtime as part of this kernel change.

## Controlled gaming benchmark

Installed candidates are Deadlock (`1422450`), Marvel Rivals (`2767030`), and Dota 2 (`570`). Use at least two, preferably all three.

### Method

1. Use the stock specialisation and CachyOS from the same generation, with the documented driver difference (`595.99.02` versus `610.57.04`) treated as a trial variable; kernel conclusions must not ignore driver effects.
2. Keep BIOS settings, monitor mode, resolution, graphics preset, Proton version, GameMode, Gamescope usage, and game build identical.
3. Pause downloads and background indexing. Reboot before each kernel's batch, wait five minutes after login, and confirm CPU/GPU temperatures are comparable.
4. Prefer a deterministic replay, training map, or fixed route. Online-match comparisons are supporting data only.
5. Run each workload three times for 5–10 minutes, discarding a run only for a documented external interruption.
6. Use a temporary per-game MangoHud launch configuration such as `autostart_log=5,log_duration=600,log_interval=100,output_folder=...`; do not change the repository's permanent MangoHud settings.
7. Record average FPS, 1% low, 0.1% low where available, median/p95/p99 frame time, CPU/GPU utilization, clocks, temperatures, power, and throttling.
8. Compute per-title medians across the three runs and retain the raw logs.

### Keep/reject threshold

Keep CachyOS only when all functional gates pass and one of these performance conditions is met:

- p99 frame time improves by at least 5% in at least two titles; or
- 1% low improves by at least 5% in at least two titles; or
- one clearly CPU-limited title improves a tail metric by at least 8%, with the other titles directionally neutral.

Additionally:

- No title may regress by more than 3% in average FPS, 1% low, or p99 frame time.
- The claimed improvement must exceed normal run-to-run variation; overlapping/noisy results are inconclusive.
- Thermal throttling, materially different clocks/power, game updates, or different Proton/settings invalidate the affected comparison.
- If differences are under 3% or inconsistent, reject the trial and retain stock. Added kernel/support churn is not justified by a tie.

## Soak period

After passing the short gates, use CachyOS for at least three normal days including one full Citrix/Zoom work session, multiple game sessions, repeated DPMS cycles, CUDA Ollama use, and normal wired/Wi-Fi/Bluetooth operation.

During the soak, check for new kernel/NVIDIA errors after each failure or reboot. Any kernel oops, hard lockup, NVRM Xid/timeout, data corruption, CUDA loss, or mandatory-workload regression ends the trial immediately.

## Rollback and recovery

### Immediate boot recovery

1. Reboot; do not power off the Hermes worker.
2. In Limine, select `stock-kernel` under the newest generation.
3. If that entry also fails, select the previously known-good generation.
4. Confirm the stock kernel, NVIDIA module, networking, and filesystem health before resuming work.

### Permanent rejection

1. Remove the host-local `boot.kernelPackages`, matching Chaotic NVIDIA override, trial tag, and stock specialisation from `modules/hosts/nixos-hyprland.nix`.
2. Remove the temporary trial wording from `README.md`; retain the corrected `r8169` note.
3. Parse and evaluate the host, then run `sudo nixos-rebuild boot --flake .#nixos`.
4. Reboot into stock, confirm the expected kernel/driver, and retain the prior generation until the system is proven stable.

`sudo nixos-rebuild boot --rollback` is an additional recovery option, but the boot-menu generation and same-generation `stock-kernel` entry are preferred because they are explicit and testable before changing profiles.

## Acceptance and final disposition

The change is complete only when:

- Focused source diff is correct and unrelated work is untouched.
- Both main and specialisation closures build successfully.
- Limine shows selectable CachyOS and stock entries plus an older generation, Secure Boot is enabled, the Limine EFI loader is signed, and Limine checksum validation is intact.
- Stock and CachyOS were tested with the same userspace; the driver difference (`595.99.02` versus `610.57.04`) is documented and included in the disposition.
- Every applicable functional gate passes.
- Benchmark logs satisfy the keep threshold.
- The three-day soak completes without a rollback trigger.
- README reflects the final retained state.

If accepted, keep the stock specialisation as a permanent emergency entry and repeat the build, boot, NVIDIA/CUDA, Citrix, DPMS, and short gaming smoke checks after future `flake.lock` updates that change either the kernel or NVIDIA version. If rejected or inconclusive, remove CachyOS and keep stock `6.18`.

## Research references

- CachyOS kernel variants and default-kernel rationale: <https://github.com/CachyOS/linux-cachyos>
- CachyOS kernel documentation: <https://wiki.cachyos.org/features/kernel/>
- CachyOS optimized CPU targets: <https://wiki.cachyos.org/features/optimized_repos/>
- NixOS specialisations: <https://wiki.nixos.org/wiki/Specialisation>
- NixOS Limine and Secure Boot: <https://wiki.nixos.org/wiki/Limine>
- Upstream kernel release support status: <https://www.kernel.org/category/releases.html>
- NVIDIA open kernel-module transition: <https://developer.nvidia.com/blog/nvidia-transitions-fully-towards-open-source-gpu-kernel-modules/>
- NVIDIA Linux driver `595.99.02` and CachyOS matching package `610.57.04`: <https://www.nvidia.com/en-us/drivers/details/278285/>
- Phoronix Zen-kernel comparison: <https://www.phoronix.com/review/arch-linux-kernels-2023>
- Phoronix CachyOS scheduler comparison: <https://www.phoronix.com/review/cachyos-bore-linux>
