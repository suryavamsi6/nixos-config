# NixOS-Config

NixOS (Hyprland / GNOME) and macOS (nix-darwin) flake configuration.

Flake hosts:

| Attribute | Desktop | Notes |
|-----------|---------|--------|
| `#nixos` | Hyprland | Primary Linux host (btrfs + Limine + Windows chainload) |
| `#plasma` | GNOME | Alternate Linux host |
| `#macbook-air` | nix-darwin | MacBook M4 Air |

---

## Dual-boot NixOS + Windows (btrfs)

This matches the `#nixos` (Hyprland) hardware module:

- Shared Windows EFI (vfat) at `/boot`
- One btrfs partition with subvolumes `@`, `@home`, `@nix`, `@log`, `@swap`
- Limine bootloader with a Windows Boot Manager entry

### 0. Prep in Windows

1. Update Windows and reboot once.
2. Disable **BitLocker** on the Windows drive (or suspend it) if enabled.
3. Disable **Fast Startup**: Control Panel → Power Options → Choose what the power buttons do → uncheck Fast Startup.
4. Free space: Disk Management → shrink `C:` (leave enough for NixOS; 80–200+ GB is typical).
5. Note your disk layout. Do **not** delete the Windows EFI System Partition (ESP).
6. Create a NixOS USB from the latest [NixOS ISO](https://nixos.org/download/).

Firmware tips:

- Boot mode: **UEFI** (not Legacy/CSM).
- For the first install, **disable Secure Boot** in firmware. This config enables Limine Secure Boot; enroll keys with `sbctl` later if you want SB back on.

### 1. Boot the installer and identify disks

```bash
lsblk -f
# EFI is usually vfat ~100–512M (Windows ESP)
# Free space = unallocated region you shrunk
```

### 2. Partition

Keep Windows partitions. In the free space create **one** Linux partition (btrfs). Reuse the existing Windows ESP — do not create a second EFI unless you know you need one.

Example with `parted` (adjust disk/partition numbers):

```bash
# Example only — verify device names first
sudo parted /dev/nvme0n1 -- print
# Create a partition in free space, type Linux filesystem, e.g. partition 5
sudo mkfs.btrfs -L nixos /dev/nvme0n1pX
```

### 3. Btrfs subvolumes

```bash
sudo mount /dev/nvme0n1pX /mnt
sudo btrfs subvolume create /mnt/@
sudo btrfs subvolume create /mnt/@home
sudo btrfs subvolume create /mnt/@nix
sudo btrfs subvolume create /mnt/@log
sudo btrfs subvolume create /mnt/@swap
sudo umount /mnt
```

### 4. Mount for install

```bash
sudo mount -o subvol=@,compress=zstd,noatime /dev/nvme0n1pX /mnt
sudo mkdir -p /mnt/{boot,home,nix,var/log,swap}
sudo mount -o subvol=@home,compress=zstd,noatime /dev/nvme0n1pX /mnt/home
sudo mount -o subvol=@nix,compress=zstd,noatime /dev/nvme0n1pX /mnt/nix
sudo mount -o subvol=@log,compress=zstd,noatime /dev/nvme0n1pX /mnt/var/log
sudo mount -o subvol=@swap,noatime /dev/nvme0n1pX /mnt/swap

# Shared Windows ESP (confirm device with lsblk -f)
sudo mount /dev/nvme0n1p1 /mnt/boot
```

### 5. Swapfile on `@swap`

```bash
# Size example: 16G — change to match RAM / preference
sudo btrfs filesystem mkswapfile --size 16g --uuid clear /mnt/swap/swapfile
sudo chmod 600 /mnt/swap/swapfile
```

### 6. Clone this flake and set UUIDs

```bash
sudo mkdir -p /mnt/home/surya
sudo git clone https://github.com/suryavamsi6/nixos-config.git /mnt/home/surya/nixos-config
cd /mnt/home/surya/nixos-config

# Read new UUIDs
lsblk -f
blkid
```

Edit `modules/hardware/hyprland-hw.nix`:

1. Replace every btrfs `by-uuid/...` with the **new** btrfs UUID.
2. Replace `/boot` `by-uuid/XXXX-XXXX` with the **Windows ESP** FAT UUID.
3. Confirm `swapDevices` still points at `/swap/swapfile`.

Optional helper (do not overwrite the flake blindly):

```bash
sudo nixos-generate-config --root /mnt --show-hardware-config
```

### 7. Install from the flake

```bash
cd /mnt/home/surya/nixos-config
sudo nixos-install --flake .#nixos
```

When prompted, set the **root** password. User `surya` has no password in the flake yet — after first boot:

```bash
sudo passwd surya
```

### 8. Reboot into Limine

1. Reboot, open firmware boot menu if needed, pick the Limine / NixOS entry.
2. You should see **NixOS** and **Windows Boot Manager**.
3. Confirm Windows still boots once.

### 9. Day-2 rebuilds

```bash
cd ~/nixos-config
sudo nixos-rebuild switch --flake .#nixos
# or, if nh is available:
nh os switch .
```

### Secure Boot (optional, later)

1. Disable Limine Secure Boot in firmware until enrollment works, **or** keep `boot.loader.limine.secureBoot.enable = true`.
2. After a successful boot with SB off, enroll keys (`sbctl`) per [NixOS Limine docs](https://wiki.nixos.org/wiki/Limine), then re-enable Secure Boot.

### Common pitfalls

- **Wrong EFI**: mounting a new empty ESP instead of the Windows one breaks chainload / Windows boot entries.
- **Stale UUIDs**: old values in `hyprland-hw.nix` will fail to mount on a fresh disk.
- **Subvolume names**: this flake expects `@`, `@home`, `@nix`, `@log`, `@swap` (not `root` / `home` — those are for `#plasma`).
- **NVIDIA**: this host assumes an NVIDIA GPU (`modules/hardware/nvidia.nix`). Change that if hardware differs.

---

## NixOS (already installed)

```bash
git clone https://github.com/suryavamsi6/nixos-config.git
cd nixos-config
sudo nixos-rebuild switch --flake .#nixos
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
