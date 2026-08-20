# NixOS-Config

NixOS (Hyprland / GNOME) and macOS (nix-darwin) flake configuration.

Flake hosts:

| Attribute | Desktop | Notes |
|-----------|---------|--------|
| `#nixos` | Hyprland | Primary Linux host (ext4 + Limine + Windows chainload) |
| `#plasma` | GNOME | Alternate Linux host |
| `#macbook-air` | nix-darwin | MacBook M4 Air |

---

## Reinstall NixOS (ext4) — nuke Samsung only

This is the weekend wipe for the **Samsung 980 PRO 1TB** (`nvme0n1`). **Do not touch** the WD_BLACK SN850X (`nvme1n1`) — that is Windows 11.

Target layout after install:

| Disk | Role |
|------|------|
| `nvme0n1` Samsung | NixOS only: 2G ESP `NIXBOOT` + one ext4 root (label `nixos`) |
| `nvme1n1` WD | Windows untouched. ESP PARTUUID `e60abccf-1a4b-4973-a37c-e20b992a9bc3` |

Limine lives on `NIXBOOT` and chainloads Windows via that GPT GUID (see `modules/boot/default.nix`).

Also: unplug the MediaTek USB Bluetooth dongle (`0e8d:0616`) and use the new **Intel** Bluetooth card before first boot of the new install.

> **Do not `nh os switch` this commit on the current btrfs install.** `hyprland-hw.nix` already expects ext4. Pull/clone it from the installer after you wipe the Samsung disk.

### 0. Prep before you wipe

1. Push any uncommitted flake work you care about (this README assumes `main` on GitHub).
2. Copy off anything only on the Samsung disk you need (`~/`, Steam under `~/.local/share/Steam`, Citrix `~/.ICAClient`, etc.). Windows files on the WD drive stay.
3. In Windows (from the WD disk):
   - Disable / suspend BitLocker if on.
   - Disable Fast Startup.
   - Confirm Windows still boots.
4. Firmware: UEFI, Secure Boot **off** for the first bring-up (Limine SB can be re-enabled later with `sbctl`).
5. Write a NixOS USB from the current [ISO](https://nixos.org/download/).
6. Physically remove / disable the MediaTek BT dongle; seat the Intel BT adapter (PCIe or USB — confirm with `lsusb` / `lspci` after the new install).

### 1. Boot the installer and confirm disks

```bash
lsblk -o NAME,SIZE,FSTYPE,LABEL,MODEL,PARTUUID
```

Expected today:

- `nvme0n1` — Samsung ~931G (NixOS — **this is what you wipe**)
- `nvme1n1` — WD ~1.8T (Windows — **leave alone**)

If labels/models are swapped on your machine, stop and rematch. Wiping the wrong NVMe destroys Windows.

### 2. Wipe and partition the Samsung disk

Only `nvme0n1`. Example with `parted` + `sgdisk`/`mkfs` (adjust if your device name differs):

```bash
# Triple-check
lsblk -o NAME,SIZE,MODEL /dev/nvme0n1

# Destroy the old GPT (Samsung ONLY)
sudo wipefs -a /dev/nvme0n1
sudo sgdisk --zap-all /dev/nvme0n1

# New GPT: 2G ESP + rest Linux
sudo parted /dev/nvme0n1 -- mklabel gpt
sudo parted /dev/nvme0n1 -- mkpart NIXBOOT fat32 1MiB 2049MiB
sudo parted /dev/nvme0n1 -- set 1 esp on
sudo parted /dev/nvme0n1 -- mkpart nixos ext4 2049MiB 100%

sudo mkfs.vfat -F 32 -n NIXBOOT /dev/nvme0n1p1
sudo mkfs.ext4 -L nixos /dev/nvme0n1p2
```

One ext4 volume is intentional: `/`, `/home`, `/nix`, `/var/log` are directories that share free space (no subvolume / size math).

### 3. Mount for install

```bash
sudo mount /dev/disk/by-label/nixos /mnt
sudo mkdir -p /mnt/boot
sudo mount /dev/disk/by-label/NIXBOOT /mnt/boot
```

### 4. Swapfile on ext4

```bash
# Match RAM / preference (16G example)
sudo fallocate -l 16G /mnt/swapfile
sudo chmod 600 /mnt/swapfile
sudo mkswap /mnt/swapfile
```

### 5. Clone the flake and set the root UUID

```bash
sudo mkdir -p /mnt/home/surya
sudo git clone https://github.com/suryavamsi6/nixos-config.git /mnt/home/surya/Dotfiles/nixos-config
cd /mnt/home/surya/Dotfiles/nixos-config

lsblk -f
blkid
```

Edit `modules/hardware/hyprland-hw.nix`:

1. Set `fileSystems."/".device` to the **new** ext4 UUID (`by-uuid/...` from `blkid` on `nvme0n1p2`), or keep `by-label/nixos` if you used `-L nixos`.
2. Leave `/boot` on `by-label/NIXBOOT`.
3. Keep `swapDevices = [ { device = "/swapfile"; } ];`.
4. Do **not** point `/boot` at the Windows ESP.

Optional check:

```bash
sudo nixos-generate-config --root /mnt --show-hardware-config
```

Use that only to copy UUIDs / kernel modules — do not replace the flake module blindly.

Confirm Windows chainload GUID in `modules/boot/default.nix` still matches:

```text
guid(e60abccf-1a4b-4973-a37c-e20b992a9bc3):/EFI/Microsoft/Boot/bootmgfw.efi
```

If Windows was repartitioned, update that PARTUUID from `lsblk -o NAME,PARTUUID /dev/nvme1n1`.

### 6. Install

```bash
cd /mnt/home/surya/Dotfiles/nixos-config
sudo nixos-install --flake .#nixos
```

Set the **root** password when prompted. After first boot:

```bash
sudo passwd surya
```

### 7. Reboot checklist

1. Firmware boot menu → Limine / NixOS on the Samsung ESP.
2. Limine should list **Windows 11** and the latest NixOS generation (`default_entry: 3` in `modules/boot/default.nix`).
3. Boot Windows once from Limine to confirm chainload.
4. On NixOS:

```bash
lsblk -f
findmnt / /boot
df -hT /
lsusb | grep -iE 'intel|8087|bluetooth'
bluetoothctl show
```

Intel BT should appear as an `hci` adapter without the MediaTek `0e8d:0616` USB id. Pair ACCENTUM Plus / MCHOSE K7 Ultra again (keys do not carry over from a wiped home).

### 8. Day-2

```bash
cd ~/Dotfiles/nixos-config
nh os switch
```

Steam library defaults to `~/.local/share/Steam` on the ext4 root — that is the point of this reinstall (no btrfs write-gap stalls on large `.ucas`).

### 9. Secure Boot (optional, later)

Keep SB off until Limine boots cleanly, then enroll keys with `sbctl` per [NixOS Limine docs](https://wiki.nixos.org/wiki/Limine) and leave `boot.loader.limine.secureBoot.enable = true`.

### Pitfalls

- **Wrong disk**: wiping `nvme1n1` destroys Windows. Match by **MODEL** and size, not only by name.
- **Shared Windows ESP**: do not mount the 100M Windows ESP at `/boot`. Kernels need the 2G `NIXBOOT` partition.
- **Stale UUIDs** in `hyprland-hw.nix` → emergency shell on first boot.
- **MediaTek still plugged in**: two adapters confuse pairing; unplug the dongle.
- **NVIDIA / r8125**: this host still expects NVIDIA + out-of-tree `r8125` (not `r8169`).

### Bluetooth notes (Intel)

- A2DP-only policy stays (no HFP autoswitch) — Citrix must not flip the headset to HFP. See `modules/audio/default.nix`.
- Do not spawn `bluetoothctl` from Serpantinum bar scripts.
- MediaTek-specific USB autosuspend udev rules are obsolete once that dongle is gone; Intel `btusb` is enough for AX200/AX210-class adapters.

---

## NixOS (already installed)

```bash
git clone https://github.com/suryavamsi6/nixos-config.git
cd nixos-config
sudo nixos-rebuild switch --flake .#nixos
# or: nh os switch
```

GNOME variant: `.#plasma`.

---

## macOS (nix-darwin) — MacBook M4 Air

1. Install Nix:

    ```bash
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
    ```

2. Clone and bootstrap:

    ```bash
    git clone https://github.com/suryavamsi6/nixos-config.git
    cd nixos-config
    nix run nix-darwin -- switch --flake .#macbook-air
    ```

3. Later rebuilds:

    ```bash
    darwin-rebuild switch --flake .#macbook-air
    ```
