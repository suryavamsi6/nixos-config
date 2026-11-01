# NixOS-Config

NixOS (Hyprland / MangoWM) and macOS (nix-darwin) flake configuration.

Flake hosts:

| Attribute | Host | Notes |
|-----------|------|-------|
| `#nixos` | Hyprland desktop | Primary Linux host (ext4 + Limine + Windows chainload) |
| `#mango` | MangoWM desktop | Experimental scrolling-tags host; see `docs/mangowm.md` |
| `#homelab` | Homelab server | Incus containers (incl. Nutify UPS monitoring), Caddy, Homepage, Gatus, restic server; see `docs/homelab.md` |
| `#raspberry-pi` | Pi | AdGuard Home, Nextcloud, Speedtest Tracker, restic targets |
| `#macbook-air` | MacBook M4 Air | nix-darwin |

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
- **NVIDIA / RTL8125**: this host uses the open NVIDIA kernel modules and the in-tree `r8169` driver for RTL8125 Ethernet.

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

### Gaming Mode (SteamOS-style gamescope session)

`#nixos` also installs a **Gaming Mode (Steam)** session that appears next to Hyprland in the greeter. It runs Steam's Deck UI on a gamescope compositor that owns the display, is remembered by `tuigreet --remember-session`, and changes nothing about the default Hyprland desktop. Details, tuning knobs and rollback: `docs/gaming-mode.md`.


### Kernel

The primary `.#nixos` host boots `pkgs.linuxPackages_cachyos-bore` with the matching NVIDIA package from the same kernel set (`modules/hosts/nixos-hyprland.nix:63`). There is no kernel specialisation: roll back by picking an older Limine generation.

Kernel changes only take effect on the next boot, so install them without touching the running session:

```bash
sudo nixos-rebuild boot --flake .#nixos
```

---

## The homelab, remotely

`#homelab` is a laptop that lives on the LAN, so most of its changes ship over the network
rather than from a shell on the machine. Two frontends drive the same NixOS
configuration (`modules/clan/`), and both are ordinary flake outputs — nothing is
deployed by hand-editing a running system.

| Command | What it does |
| --- | --- |
| `deploy .#homelab` | Builds locally, activates remotely over SSH. Fails the whole run if the remote activation fails. |
| `deploy .#raspberry-pi` | Same, for the pi. Add `--remote-build` to build on the pi instead (slow, but it survives a broken local store). |
| `clan machines update homelab` | Clan's wrapper around the same deploy nodes. |
| `clan machines update raspberry-pi` | Same, for the pi. |
| `clan vars list homelab` | Lists Clan-managed secrets for a machine, and whether each is adopted. |
| `clan vars upload homelab` | Pushes secret ciphertext to the host. **Required** before a deploy that changes a secret — the store is external, so it is not in the closure. |
| `./scripts/clan-adopt-secrets.sh --list` | Which secrets still need adopting, and from which live file. |
| `./scripts/clan-adopt-secrets.sh raspberry-pi` | Adopt the pi's restic credentials into the store. |

`deploy` with no argument is a dry run: it builds and prints the profile it *would*
activate, which is the safe way to check a change before touching the homelab.

The two hosts that are reachable over the network are `#homelab` and `#raspberry-pi`.
There are no deploy nodes for `#nixos`, `#mango` or `#macbook-air`: they are the
machines you are sitting at, and they take `nh os switch` / `darwin-rebuild switch`
directly.

Clan CLI quirk worth knowing: `--flake` is an option of the *subcommand*, not a global
flag. `clan --flake . vars list homelab` fails with `invalid choice: '.'`; from the
repository root you do not need it at all (`clan vars list homelab`).

Remote activation needs sudo on the target. The deploy nodes are configured for
interactive sudo — a password prompt appears in your terminal — so run these from a
normal shell, not from a script.

### Secrets

Every credential on `#homelab`, `#raspberry-pi` and `#nixos` is a **Clan var**, decrypted
to `/run/secrets` on boot instead of being written into `/var/lib` by a first-boot
oneshot. The ciphertext lives outside this repo (`$CLAN_AGE_STORE_DIR`, default
`~/clan-secrets`) because the flake is public, so export it for any `clan vars` call:

```bash
export CLAN_AGE_STORE_DIR=$HOME/clan-secrets
clan vars list homelab                    # what exists, and whether it is adopted
clan vars upload homelab                  # push ciphertext before a deploy that changes one
```

No generator mints a value. `clan vars generate` on a missing secret prints the
adoption command and exits non-zero, because every one of these credentials is
entangled with a live service — rotating the Qdrant key breaks Bifrost's vector-store
config, rotating a Booklore DB password desynchronises it from MariaDB, rotating the
restic pair makes every client's nightly push fail 401 into an unrecoverable repo.
Adoption is one script — idempotent, and it normalises the shapes that
`incus config show --expanded` emits (`environment.KEY: value` → `KEY=value`):

```bash
./scripts/clan-adopt-secrets.sh --list       # what is left, and from where
./scripts/clan-adopt-secrets.sh raspberry-pi # no sudo needed
./scripts/clan-adopt-secrets.sh homelab      # prompts for sudo — must be a real terminal
```

The `sudo` targets cannot run from a pipe: the value is read inside `$(…)`, which is a
pipe, so a remote `sudo` there neither prompts nor proceeds — it just waits. The script
refuses up front rather than hanging. Full model, breakage table and the two deliberate
exceptions (`restic-htpasswd` under `PrivateUsers`, Homepage's 0644 env file):
`docs/homelab.md` §"Secrets (Clan vars)".

---

## Monitoring, backups, disk health

`modules/monitoring/` adds SMART disk health and nightly restic backups to `#nixos`, `#homelab`, and `#raspberry-pi`; the homelab's Homepage, Gatus, and Netdata pages surface both. Setup, restore procedure, and the exclusion list: `docs/homelab.md`.

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
