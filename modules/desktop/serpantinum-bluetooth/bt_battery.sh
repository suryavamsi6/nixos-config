#!/usr/bin/env bash
set -u

bt_adapter() {
  busctl --system tree org.bluez --list 2>/dev/null \
    | grep -E '^/org/bluez/hci[0-9]+$' \
    | head -n1
}

bt_prop() {
  busctl --system get-property org.bluez "$1" "$2" "$3" 2>/dev/null
}

bt_bool() {
  bt_prop "$@" | grep -q 'true'
}

bt_str() {
  bt_prop "$@" | sed -n 's/^s "\(.*\)"$/\1/p'
}

bt_byte() {
  bt_prop "$@" | awk '/^y / { print $2; exit }'
}

bt_devices() {
  local adapter
  adapter=$(bt_adapter)
  [ -n "$adapter" ] || return 0
  busctl --system tree org.bluez --list 2>/dev/null \
    | grep -E "^${adapter}/dev_[^/]+$"
}

bt_battery_dir() {
  printf '%s\n' "${XDG_RUNTIME_DIR:-/tmp}/qs-bt-battery"
}

bt_cache_set() {
  local device=$1 level=$2 address dir
  address=$(bt_str "$device" org.bluez.Device1 Address)
  [ -n "$address" ] && [[ $level =~ ^[0-9]+$ ]] && [ "$level" -le 100 ] || return 0
  dir=$(bt_battery_dir)
  mkdir -p "$dir"
  printf '%s\n' "$level" > "$dir/$address"
}

bt_cache_get() {
  local device=$1 address dir age level
  address=$(bt_str "$device" org.bluez.Device1 Address)
  dir=$(bt_battery_dir)
  [ -n "$address" ] && [ -f "$dir/$address" ] || return 0
  age=$(($(date +%s) - $(stat -c %Y "$dir/$address" 2>/dev/null || echo 0)))
  [ "$age" -lt 1200 ] || return 0
  level=$(tr -d '[:space:]' < "$dir/$address")
  [[ $level =~ ^[0-9]+$ ]] && [ "$level" -le 100 ] && printf '%s\n' "$level"
}

bt_2a19_path() {
  local device=$1 address dir cached characteristic uuid
  address=$(bt_str "$device" org.bluez.Device1 Address)
  dir=$(bt_battery_dir)
  mkdir -p "$dir"
  cached="$dir/${address}.char"

  if [ -f "$cached" ]; then
    characteristic=$(tr -d '[:space:]' < "$cached")
    uuid=$(bt_str "$characteristic" org.bluez.GattCharacteristic1 UUID)
    case "${uuid,,}" in
      00002a19-0000-1000-8000-00805f9b34fb)
        printf '%s\n' "$characteristic"
        return 0
        ;;
    esac
  fi

  while IFS= read -r characteristic; do
    [ -n "$characteristic" ] || continue
    uuid=$(bt_str "$characteristic" org.bluez.GattCharacteristic1 UUID)
    case "${uuid,,}" in
      00002a19-0000-1000-8000-00805f9b34fb)
        printf '%s\n' "$characteristic" > "$cached"
        printf '%s\n' "$characteristic"
        return 0
        ;;
    esac
  done < <(
    busctl --system tree org.bluez --list 2>/dev/null \
      | grep -E "^${device}/service[^/]+/char[^/]+$"
  )
}

bt_gatt_level() {
  local characteristic value level
  characteristic=$(bt_2a19_path "$1")
  [ -n "$characteristic" ] || return 0
  value=$(busctl --system --timeout=3 call org.bluez "$characteristic" \
    org.bluez.GattCharacteristic1 ReadValue 'a{sv}' 0 2>/dev/null) || return 0
  level=$(awk '/^ay / { print $NF; exit }' <<< "$value")
  [[ $level =~ ^[0-9]+$ ]] && [ "$level" -le 100 ] && printf '%s\n' "$level"
}

bt_battery() {
  local device=$1 level
  level=$(bt_byte "$device" org.bluez.Battery1 Percentage)
  [ -n "$level" ] || level=$(bt_gatt_level "$device")
  if [ -n "$level" ]; then
    bt_cache_set "$device" "$level"
    printf '%s\n' "$level"
    return 0
  fi
  bt_cache_get "$device"
}

bt_is_audio() {
  local icon uuids
  icon=$(bt_str "$1" org.bluez.Device1 Icon)
  case "$icon" in
    audio-headset|audio-headphones|audio-card) return 0 ;;
  esac
  uuids=$(bt_prop "$1" org.bluez.Device1 UUIDs)
  grep -q '0000110b-0000-1000-8000-00805f9b34fb' <<< "$uuids"
}

# Dual-mode headsets expose 0x2A19 only on the LE bearer. Take one snapshot,
# then disconnect LE so A2DP does not share the radio.
#
# Two things matter here, and both were wrong before:
#  * `Bearer.LE1 Connect` returns immediately with "In Progress". It does not
#    block until the link is up, so polling for the value straight afterwards
#    only ever reads "Not connected". We have to wait on the bearer's own
#    Connected property instead of guessing a sleep.
#  * A device bonded only over BR/EDR (LE1 Bonded=false) can spend the whole
#    timeout failing to bring LE up. Record that, back off for a while, and do
#    NOT hold the lock for the entire attempt or every later run is skipped.
bt_le_wait_connected() {
  local device=$1 deadline=$((SECONDS + 20)) state
  while [ $SECONDS -lt $deadline ]; do
    state=$(bt_prop "$device" org.bluez.Bearer.LE1 Connected | awk '/^b / {print $2; exit}')
    [ "$state" = "true" ] && return 0
    sleep 0.5
  done
  return 1
}

bt_refresh_audio_battery() {
  local device=$1 address dir stamp lock age level
  bt_is_audio "$device" || return 0
  [ -n "$(bt_prop "$device" org.bluez.Bearer.LE1 Connected)" ] || return 0

  address=$(bt_str "$device" org.bluez.Device1 Address)
  dir=$(bt_battery_dir)
  mkdir -p "$dir"

  # Back off further after a failed attempt: bringing an unbonded LE bearer up
  # costs a full connect timeout, so retrying every minute is wasted work.
  stamp="$dir/${address}.le-fail"
  if [ -f "$stamp" ]; then
    age=$(($(date +%s) - $(stat -c %Y "$stamp" 2>/dev/null || echo 0)))
    [ "$age" -lt 300 ] && return 0
  fi

  lock="${XDG_RUNTIME_DIR:-/tmp}/qs-bt-battery.lock"
  if [ -d "$lock" ]; then
    age=$(($(date +%s) - $(stat -c %Y "$lock" 2>/dev/null || echo 0)))
    [ "$age" -gt 40 ] && rmdir "$lock" 2>/dev/null || true
  fi
  mkdir "$lock" 2>/dev/null || return 0

  level=""
  if bt_bool "$device" org.bluez.Bearer.LE1 Connected || bt_le_wait_connected "$device"; then
    :
  elif busctl --system --timeout=20 call org.bluez "$device" \
      org.bluez.Bearer.LE1 Connect >/dev/null 2>&1 && bt_le_wait_connected "$device"; then
    :
  fi

  if [ "$(bt_prop "$device" org.bluez.Bearer.LE1 Connected | awk '/^b / {print $2; exit}')" = "true" ]; then
    level=$(bt_byte "$device" org.bluez.Battery1 Percentage)
    [ -n "$level" ] || level=$(bt_gatt_level "$device")
    [ -n "$level" ] && bt_cache_set "$device" "$level"
    busctl --system --timeout=5 call org.bluez "$device" \
      org.bluez.Bearer.LE1 Disconnect >/dev/null 2>&1 || true
  fi

  rmdir "$lock" 2>/dev/null || true

  if [ -n "$level" ]; then
    rm -f "$stamp"
  else
    touch "$stamp"
  fi
}

emit_batteries() {
  local device address address_lower level
  while IFS= read -r device; do
    [ -n "$device" ] || continue
    bt_bool "$device" org.bluez.Device1 Connected || continue
    address=$(bt_str "$device" org.bluez.Device1 Address)
    [ -n "$address" ] || continue

    level=$(bt_battery "$device")
    if [ -z "$level" ] && bt_is_audio "$device"; then
      bt_refresh_audio_battery "$device"
      level=$(bt_cache_get "$device")
    fi
    [ -n "$level" ] || continue

    address_lower=${address,,}
    printf '%s\037%s\n' "$address_lower" "$level"
  done < <(bt_devices)
}

if [ -z "$(bt_adapter)" ]; then
  printf '{}\n'
  exit 0
fi

emit_batteries | jq -R -s -c '
  split("\n")
  | map(select(length > 0) | split("\u001f") | {key: .[0], value: (.[1] | tonumber)})
  | from_entries
'
