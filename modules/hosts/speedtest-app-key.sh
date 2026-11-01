#!/usr/bin/env bash
# Ensure Speedtest Tracker has a usable Laravel APP_KEY.
#
# Usage: speedtest-app-key.sh /mnt/media/speedtest-tracker/speedtest.env
#
# Why this exists as a file rather than an inline systemd script: the repair
# needs to strip a literal backslash-n suffix, and expressing that through a
# Nix indented string takes enough escaping levels that the generated shell
# silently changes meaning. Plain bash here is verifiable.
#
# History: an earlier version of the unit wrote the key with
# `printf 'APP_KEY=%s\\n'`, which printf emitted as a literal backslash + n
# instead of a newline. Laravel then rejected every request with
# "Unsupported cipher or incorrect key length" — an HTTP 500 on the dashboard
# while the container itself reported healthy.
#
# Three traps this script has already been bitten by, all worth preserving:
#   * `base64 -d` SKIPS invalid characters and only then reports failure, so
#     a key with a trailing "\\n" still decodes 32 bytes and looks valid.
#     Require both a zero exit status and exactly 32 decoded bytes.
#   * a glob pattern `\\n` inside `${key%...}` matches a bare `n`, because the
#     backslash escapes the n. Match the two-character sequence explicitly
#     with the `[[ $key == *\\\\n ]]` pattern plus `${key%??}`.
#   * the decode must not go through a bash variable: 32 random bytes can
#     contain a NUL, which bash silently truncates, so count with wc -c.
#
# Behaviour: keep the existing key whenever it is genuinely usable (so sessions
# and encrypted settings survive), otherwise mint a fresh one.
set -euo pipefail

envFile=${1:?usage: speedtest-app-key.sh <env-file>}

key=""
if [ -s "$envFile" ]; then
  key=$(sed -n 's/^APP_KEY=//p' "$envFile" | tr -d '[:space:]')
  # Strip any trailing literal backslash-n left by the old writer. Only the
  # exact two-character sequence is removed, so a key legitimately ending in
  # "n" or "\" is left alone.
  while [[ "$key" == *"\\n" ]]; do
    key=${key%??}
  done
fi

valid=0
case "$key" in
  base64:*)
    if decoded_len=$(printf '%s' "${key#base64:}" | base64 -d 2>/dev/null | wc -c) \
      && [ "$decoded_len" -eq 32 ]; then
      valid=1
    fi
    ;;
esac

if [ "$valid" -ne 1 ]; then
  key="base64:$(openssl rand -base64 32 | tr -d '\n')"
fi

echo "APP_KEY=$key" > "$envFile"
