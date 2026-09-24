#!/usr/bin/env bash
set -euo pipefail

raw="$(apcaccess status 2>/dev/null || true)"

value() {
  local key="$1"
  awk -F: -v key="$key" '$1 ~ "^[[:space:]]*" key "[[:space:]]*$" { sub(/^[[:space:]]+/, "", $2); sub(/[[:space:]]+$/, "", $2); print $2; exit }' <<<"$raw"
}

number() {
  local result
  result="$(value "$1")"
  awk '{ if ($1 ~ /^-?[0-9]+([.][0-9]+)?$/) print $1; else print 0 }' <<<"$result"
}

status="$(value STATUS)"
model="$(value MODEL)"
last_transfer="$(value LASTXFER)"

jq -n \
  --arg status "${status:-Unavailable}" \
  --arg model "${model:-APC UPS}" \
  --arg lastTransfer "${last_transfer:-Unknown}" \
  --argjson charge "$(number BCHARGE)" \
  --argjson load "$(number LOADPCT)" \
  --argjson runtime "$(number TIMELEFT)" \
  --argjson batteryVoltage "$(number BATTV)" \
  --argjson nominalBatteryVoltage "$(number NOMBATTV)" \
  '{status: $status, model: $model, lastTransfer: $lastTransfer,
    charge: $charge, load: $load, runtime: $runtime,
    batteryVoltage: $batteryVoltage,
    nominalBatteryVoltage: $nominalBatteryVoltage}'
