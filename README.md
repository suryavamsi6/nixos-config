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

Wipe the **Samsung 980 PRO 1TB** only. Identify by **MODEL**, not `nvmeN` (names swap). On this machine Samsung is currently `nvme1n1` and the WD_BLACK SN850X (Windows 11) is `nvme0n1`.

Live layout:

| Disk | Role |
|------|------|
| Samsung 980 PRO (`nvme1n1` today) | NixOS: ~1G ESP UUID `EC21-2EC2` at `/boot`, ext4 root, swap partition |
| WD SN850X (`nvme0n1` today) | Windows untouched. ESP PARTUUID `e60abccf-1a4b-4973-a37c-e20b992a9bc3` |

Limine lives on the NixOS ESP and chainloads Windows via that GPT GUID (see `modules/boot/default.nix`).

Wi-Fi/BT is **MediaTek MT7922** (PCIe + USB `0e8d:0616`). That USB id is the combo card, not a dongle — do not unplug it.

### 0. Prep before you wipe

1. Push any uncommitted flake work you care about (this README assumes `main` on GitHub).
2. Copy off anything only on the Samsung disk you need (`~/`, Steam under `~/.local/share/Steam`, Citrix `~/.ICAClient`, etc.). Windows files on the WD drive stay.
3. In Windows (from the WD disk):
   - Disable / suspend BitLocker if on.
   - Disable Fast Startup.
   - Confirm Windows still boots.
4. Firmware: UEFI, Secure Boot **off** for the first bring-up (Limine SB can be re-enabled later with `sbctl`).
5. Write a NixOS USB from the current [ISO](https://nixos.org/download/).
6. Leave the MT7922 combo card in place (`lsusb` should still show `0e8d:0616`).

### 1. Boot the installer and confirm disks

```bash
lsblk -o NAME,SIZE,FSTYPE,LABEL,MODEL,PARTUUID
```

Expected today:

- `nvme1n1` — Samsung ~931G (NixOS — **this is what you wipe**)
- `nvme0n1` — WD ~1.8T (Windows — **leave alone**)

If names are swapped on your machine, stop and rematch by **MODEL**. Wiping the WD SN850X destroys Windows.

### 2. Wipe and partition the Samsung disk

Only the Samsung 980 PRO. Example uses `nvme1n1` (today's name); confirm MODEL first:

```bash
# Triple-check
lsblk -o NAME,SIZE,MODEL /dev/nvme1n1

# Destroy the old GPT (Samsung ONLY)
sudo wipefs -a /dev/nvme1n1
sudo sgdisk --zap-all /dev/nvme1n1

# New GPT: 1G ESP + rest Linux (match the live ~1G ESP, or use 2G if you prefer)
sudo parted /dev/nvme1n1 -- mklabel gpt
sudo parted /dev/nvme1n1 -- mkpart ESP fat32 1MiB 1025MiB
sudo parted /dev/nvme1n1 -- set 1 esp on
sudo parted /dev/nvme1n1 -- mkpart nixos ext4 1025MiB 100%

sudo mkfs.vfat -F 32 /dev/nvme1n1p1
sudo mkfs.ext4 -L nixos /dev/nvme1n1p2
```

One ext4 volume is intentional: `/`, `/home`, `/nix`, `/var/log` are directories that share free space (no subvolume / size math).

### 3. Mount for install

```bash
sudo mount /dev/disk/by-label/nixos /mnt
sudo mkdir -p /mnt/boot
sudo mount /dev/nvme1n1p1 /mnt/boot
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

1. Set `fileSystems."/".device` to the **new** ext4 UUID (`by-uuid/...` from `blkid` on the Samsung root), or keep `by-label/nixos` if you used `-L nixos`.
2. Set `/boot` to the new NixOS ESP UUID. Do not use the Windows ESP.
3. Point `swapDevices` at the new swap UUID (or `/swapfile` if you used a file).

Optional check:

```bash
sudo nixos-generate-config --root /mnt --show-hardware-config
```

Use that only to copy UUIDs / kernel modules — do not replace the flake module blindly.

Confirm Windows chainload GUID in `modules/boot/default.nix` still matches:

```text
guid(e60abccf-1a4b-4973-a37c-e20b992a9bc3):/EFI/Microsoft/Boot/bootmgfw.efi
```

If Windows was repartitioned, update that PARTUUID from `lsblk -o NAME,MODEL,PARTUUID` on the WD SN850X.

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
lsusb | grep -iE 'mediatek|0e8d|bluetooth'
rfkill list bluetooth
```

MT7922 should appear as an `hci` adapter (`lsusb` still shows `0e8d:0616`). Pair ACCENTUM Plus / MCHOSE K7 Ultra again (keys do not carry over from a wiped home).

### 8. Day-2

```bash
cd ~/Dotfiles/nixos-config
nh os switch
```

Steam library defaults to `~/.local/share/Steam` on the ext4 root — that is the point of this reinstall (no btrfs write-gap stalls on large `.ucas`).

### 9. Secure Boot (optional, later)

Keep SB off until Limine boots cleanly, then enroll keys with `sbctl` per [NixOS Limine docs](https://wiki.nixos.org/wiki/Limine) and leave `boot.loader.limine.secureBoot.enable = true`.

### Pitfalls

- **Wrong disk**: wiping the WD SN850X destroys Windows. Match by **MODEL** and size, not `nvmeN`.
- **Shared Windows ESP**: do not mount the 100M Windows ESP at `/boot`. Kernels need the NixOS ESP (~1G on the Samsung SSD).
- **Stale UUIDs** in `hyprland-hw.nix` → emergency shell on first boot.
- **NVIDIA / r8125**: this host still expects NVIDIA + out-of-tree `r8125` (not `r8169`).

### Bluetooth notes (MT7922)

- A2DP-only policy stays (no HFP autoswitch) — Citrix must not flip the headset to HFP. See `modules/audio/default.nix`.
- Do not spawn `bluetoothctl` from Serpantinum bar scripts.
- USB id `0e8d:0616` is the onboard combo card. Do not unplug it. `Powered=false` rfkill-softblocks it; `rfkill unblock bluetooth` runs before BlueZ.

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
