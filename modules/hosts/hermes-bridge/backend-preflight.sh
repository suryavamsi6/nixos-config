#!/bin/sh
# ExecStartPre for hermes-bridge-backend (pushed into the container by incus-hermes-bridge).
set -u

# 1. The unit sets HERMES_DASHBOARD_PUBLIC_URL=http://127.0.0.1:<port> so a LAN dashboard.public_url in
#    config.yaml does not put this private backend behind Hermes's browser login. Hermes loads
#    ~/.hermes/.env OVER the process environment, so a non-blank value there would undo that.
#    Checks for the key only; never prints the value.
envfile="${HERMES_HOME:-$HOME/.hermes}/.env"
if [ -f "$envfile" ] && grep -Eq '^[[:space:]]*(export[[:space:]]+)?HERMES_DASHBOARD_PUBLIC_URL[[:space:]]*=[[:space:]]*["'"'"']?[^[:space:]"'"'"'#]' "$envfile"; then
  echo "hermes-bridge-backend: $envfile sets HERMES_DASHBOARD_PUBLIC_URL, which overrides this unit's loopback" >&2
  echo "value and would put the private backend behind the browser login. Move that setting to" >&2
  echo "dashboard.public_url in config.yaml (same effect for the :9119 dashboard), then restart both." >&2
  exit 1
fi

# 2. Let the browser dashboard (:9119) claim Hermes's host-backend record first: a headless backend
#    holding it would make a later `hermes dashboard` restart refuse to start (exit 78).
i=0
while [ "$i" -lt 60 ]; do
  if curl -fsS -o /dev/null http://127.0.0.1:9119/api/health; then sleep 5; exit 0; fi
  i=$((i + 1)); sleep 2
done
echo "hermes-bridge-backend: the dashboard on :9119 is not up" >&2
exit 1
