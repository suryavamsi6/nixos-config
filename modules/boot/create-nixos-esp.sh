#!/usr/bin/env bash
# Shrink nvme1n1p1 GPT to match the already-resized btrfs, then create a
# FAT32 ESP labeled NIXBOOT. Safe to re-run if p2 already exists.
set -euo pipefail

export PATH="/run/current-system/sw/bin:$PATH"

DISK=/dev/nvme1n1
P1=${DISK}p1
P2=${DISK}p2
MIN_ESP_BYTES=$((1024 * 1024 * 1024))

if [[ $EUID -ne 0 ]]; then
  echo "run as root (sudo $0)" >&2
  exit 1
fi

fstype=$(lsblk -no FSTYPE "$P1")
label=$(lsblk -no LABEL "$P1")
if [[ "$fstype" != "btrfs" || "$label" != "nixos" ]]; then
  echo "refusing: $P1 is '$fstype'/'$label', expected btrfs/nixos" >&2
  exit 1
fi

slack_bytes=$(btrfs filesystem usage -b / | awk '/Device slack:/ {print $3; exit}')
slack_bytes=${slack_bytes:-0}

if [[ ! -b "$P2" ]]; then
  if (( slack_bytes < MIN_ESP_BYTES )); then
    echo "shrinking btrfs on / by -1G (slack was $slack_bytes)"
    btrfs filesystem resize -1G /
    slack_bytes=$(btrfs filesystem usage -b / | awk '/Device slack:/ {print $3; exit}')
  fi

  if (( slack_bytes < MIN_ESP_BYTES )); then
    echo "refusing: btrfs slack $slack_bytes < 1GiB" >&2
    exit 1
  fi

  START=$(cat /sys/block/nvme1n1/nvme1n1p1/start)
  SIZE=$(cat /sys/block/nvme1n1/nvme1n1p1/size)
  SLACK_SECTORS=$((slack_bytes / 512))
  # Keep 1MiB alignment
  SLACK_SECTORS=$((SLACK_SECTORS / 2048 * 2048))
  NEW_SIZE=$((SIZE - SLACK_SECTORS))
  P2_START=$((START + NEW_SIZE))

  if (( NEW_SIZE <= 0 || P2_START <= START )); then
    echo "refusing: bad geometry start=$START size=$SIZE slack_sectors=$SLACK_SECTORS" >&2
    exit 1
  fi

  echo "GPT: shrink $P1 to $NEW_SIZE sectors, ESP starts at $P2_START"
  printf ',%s\n' "$NEW_SIZE" | sfdisk --force --no-reread -N 1 "$DISK"
  printf 'start=%s, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name=NIXBOOT\n' "$P2_START" \
    | sfdisk --force --no-reread --append "$DISK"

  partprobe "$DISK" || true
  udevadm settle || true
  sleep 1

  if [[ ! -b "$P2" ]]; then
    echo "failed to create $P2" >&2
    lsblk "$DISK" >&2
    sfdisk -d "$DISK" >&2
    exit 1
  fi

  mkfs.vfat -F 32 -n NIXBOOT "$P2"
fi

if ! findmnt -n -S LABEL=NIXBOOT >/dev/null 2>&1; then
  echo "unmounting Windows ESP from /boot (files stay; firmware can still boot it)"
  umount /boot
  mount -o fmask=0022,dmask=0022 LABEL=NIXBOOT /boot
fi

echo
echo "NIXBOOT is mounted at /boot:"
df -h /boot
lsblk -o NAME,SIZE,FSTYPE,LABEL,UUID,MOUNTPOINT "$DISK"
echo
echo "Next: nh os boot"
