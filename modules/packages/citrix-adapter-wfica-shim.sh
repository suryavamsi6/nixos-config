#! /usr/bin/env bash
# AuthManager forks $ICAROOT/adapter as its UIPipe child for store→HDX
# launches. The vendor adapter waits on a session hash over that pipe and,
# when ServiceRecord cannot supply one, exits in ~10s without ever starting
# wfica. The same ICA file launched as `wfica -icaroot … file.ICA` works.
# Strip UIPipe-only flags and exec wfica directly.
set -euo pipefail

icaroot="${ICAROOT:-}"
icafile=""
display="${DISPLAY:-}"

args=("$@")
i=0
n=${#args[@]}
while ((i < n)); do
  a="${args[i]}"
  case "$a" in
  -icaroot)
    ((++i))
    icaroot="${args[i]:-}"
    ;;
  -file)
    ((++i))
    icafile="${args[i]:-}"
    ;;
  --display)
    ((++i))
    display="${args[i]:-}"
    ;;
  -WI | -casEnabledStore | -transactionid | -connectionid | -parentDeviceId | -qlaunch)
    ((++i))
    ;;
  *.ICA | *.ica)
    icafile="$a"
    ;;
  esac
  ((++i))
done

if [[ -z "$icaroot" ]]; then
  self="$(readlink -f "$0" 2>/dev/null || realpath "$0")"
  dir="$(dirname "$self")"
  if [[ -x "$dir/wfica" ]]; then
    icaroot="$dir"
  elif [[ -e /opt/Citrix/ICAClient/wfica ]]; then
    icaroot="$(readlink -f /opt/Citrix/ICAClient)"
  fi
fi

if [[ -z "$icaroot" || -z "$icafile" ]]; then
  echo "citrix-adapter-wfica-shim: need ICAROOT and an ICA file (argv: $*)" >&2
  exit 1
fi

export ICAROOT="$icaroot"
# Force X11 — inherited WAYLAND/GDK=wayland crashes WebKit/wfica on NVIDIA.
export GDK_BACKEND=x11
export EGL_PLATFORM=x11
export QT_QPA_PLATFORM=xcb
unset QT_QPA_PLATFORMTHEME || true
export WEBKIT_DISABLE_COMPOSITING_MODE=1
export WEBKIT_DISABLE_DMABUF_RENDERER=1
if [[ -n "$display" ]]; then
  export DISPLAY="$display"
fi

exec "$icaroot/wfica" -icaroot "$icaroot" "$icafile"
