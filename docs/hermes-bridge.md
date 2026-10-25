# hermes-bridge on the homelab

hermes-bridge is a small management API for the Hermes phone app. It covers profiles, per-profile
chat keys, MCP servers, routines, skills, toolsets, plugins and memory settings. It forwards an
allowlist of the Hermes dashboard's REST API and never exposes the dashboard itself: no terminal,
files, secret reveal or raw env reads.

The package is generic: it lives in its own project and is vendored here unchanged in
`modules/hosts/hermes-bridge/hermes_bridge/`. This repo only adds the homelab glue in
`modules/hosts/hermes-bridge/default.nix`.

## What runs where

| Piece | Where | Reachable from |
|---|---|---|
| `hermes-dashboard` (unchanged) | container, 0.0.0.0:9119, basic auth | LAN through Caddy (hermes.home.arpa) |
| `hermes-bridge-backend` (`hermes serve --isolated`) | container, **127.0.0.1:9120**, fixed session token | the bridge only |
| `hermes-bridge` | container, 10.110.0.50:8765 | this host, then Tailscale Funnel at `/bridge` |
| Hermes API server (unchanged) | container, :8642 | Tailscale Funnel at `/` |

Both new services are systemd **user** units of `hermes` inside the container, pushed by the host
unit `incus-hermes-bridge`. The private backend starts only after the browser dashboard answers on
:9119. That way the dashboard keeps Hermes's "host backend" record; a headless backend holding it
would make the dashboard's next restart refuse to start.

Secrets are created once on this host, root-only, and never printed or rotated by the unit:

- `/var/lib/incus/hermes/bridge-key`: the key you type into the app.
- `/var/lib/incus/hermes/bridge-dashboard-token`: shared by the bridge and its private backend.

## Deploy

The new directory must be tracked by git for the flake to see it (staging is enough). Run the
`git add` again after any change to it, so new files such as `backend-preflight.sh` are included:

```bash
cd ~/Dotfiles/nixos-config
git add modules/hosts/hermes-bridge docs/hermes-bridge.md
nixos-rebuild switch --flake .#homelab --target-host surya@homelab.home.arpa --sudo
```

## Check it (on the homelab)

```bash
systemctl status incus-hermes-bridge hermes-funnel
sudo incus exec hermes -- sudo -iu hermes systemctl --user status hermes-bridge-backend hermes-bridge
curl -s http://10.110.0.50:8765/v1/health                               # {"ok": true, ...}
sudo tailscale funnel status                                             # / -> :8642 and /bridge -> :8765
curl -s https://<host>.<tailnet>.ts.net/bridge/v1/health                 # same, over the internet
curl -s -H "Authorization: Bearer $(sudo cat /var/lib/incus/hermes/bridge-key)" \
  http://10.110.0.50:8765/v1/status | jq '.ok, .hermes, .message'        # compatibility report
```

If `/v1/status` is not ok, its `message` says why: dashboard down, token mismatch, a
login-protected backend (see below), or an API change after a `hermes update`.

## "The dashboard backend requires a browser login" (`dashboard_gated`)

Hermes puts a dashboard process behind browser login when it binds a non-loopback address, **or**
when `dashboard.public_url` (config.yaml) or `HERMES_DASHBOARD_PUBLIC_URL` names a non-loopback host.
The second case applies even to a backend on 127.0.0.1 (`hermes_cli/web_server_boundary.py`,
`public_hosts_engage_gate`). The LAN dashboard's public URL therefore gated the private backend too.

The fix is in `hermes-bridge-backend.service`:
- It sets `HERMES_DASHBOARD_PUBLIC_URL=http://127.0.0.1:9120` for that process only. The env var
  takes precedence over config.yaml, so the backend stays in session-token mode, and the :9119
  dashboard keeps its own setting.
- Hermes loads `~/.hermes/.env` *over* the process environment (`hermes dashboard register` writes
  this key there). So `backend-preflight.sh` refuses to start, with a message in the journal, if
  `.env` sets the key.

Diagnose (nothing below prints a key or token):

```bash
# Is the private backend gated? Expect "auth_required": false. (The :9119 dashboard may say true.)
sudo incus exec hermes -- curl -s http://127.0.0.1:9120/api/health | jq '{ok, version, auth_required}'
sudo incus exec hermes -- curl -s http://127.0.0.1:9119/api/health | jq '{ok, auth_required}'

# Who listens where: 9120 must be 127.0.0.1 only; 8765 on 10.110.0.50; 9119 and 8642 unchanged.
sudo incus exec hermes -- ss -ltnp | grep -E ':(8642|8765|9119|9120)\b'

# Unit state and recent logs (the preflight explains itself here).
sudo incus exec hermes -- su - hermes -c 'XDG_RUNTIME_DIR=/run/user/$(id -u) systemctl --user status hermes-bridge-backend hermes-bridge --no-pager'
sudo incus exec hermes -- su - hermes -c 'XDG_RUNTIME_DIR=/run/user/$(id -u) journalctl --user -u hermes-bridge-backend -u hermes-bridge -n 60 --no-pager'
systemctl status incus-hermes-bridge --no-pager; journalctl -u incus-hermes-bridge -n 30 --no-pager

# Where is a public URL declared? Prints line numbers and key names only, never values.
sudo incus exec hermes -- grep -nE '^[[:space:]]*public_url[[:space:]]*:' /home/hermes/.hermes/config.yaml | cut -d: -f1,2
sudo incus exec hermes -- grep -nE '^[[:space:]]*(export[[:space:]]+)?HERMES_DASHBOARD_PUBLIC_URL[[:space:]]*=' /home/hermes/.hermes/.env | cut -d= -f1

# The env the running backend actually started with (only this one variable; it is not a secret).
sudo incus exec hermes -- sh -c 'tr "\0" "\n" < /proc/$(pgrep -u hermes -f "serve --isolated" | head -1)/environ | grep "^HERMES_DASHBOARD_PUBLIC_URL="'

# The bridge reaches the backend over loopback inside the container (expect http://127.0.0.1:9120).
sudo incus exec hermes -- grep -h DASHBOARD_URL /home/hermes/.config/systemd/user/hermes-bridge.service

# End to end: expect true, then the Hermes version.
curl -s -H "Authorization: Bearer $(sudo cat /var/lib/incus/hermes/bridge-key)" \
  http://10.110.0.50:8765/v1/status | jq '.ok, .hermes.version, .code'
```

If the `.env` grep printed `HERMES_DASHBOARD_PUBLIC_URL`, move that setting to config.yaml. The
dashboard reads it from either place, so :9119 behaves the same. Then restart:

```bash
sudo incus exec hermes -- su - hermes   # then, as hermes inside the container:
#   nano ~/.hermes/.env      -> copy the URL, delete the HERMES_DASHBOARD_PUBLIC_URL line
#   hermes config set dashboard.public_url '<that URL>'
#   XDG_RUNTIME_DIR=/run/user/$(id -u) systemctl --user restart hermes-dashboard hermes-bridge-backend hermes-bridge
```

## Phone app

Settings → Hermes bridge: the URL is `https://<host>.<tailnet>.ts.net/bridge` (pre-filled from the
server URL), and the key is the output of `sudo cat /var/lib/incus/hermes/bridge-key`.

## Undo

Set `services.hermesBridge.enable = false;` and deploy. The Funnel job stops adding `/bridge` but
doesn't remove it, so also run `sudo tailscale funnel --https=443 --set-path /bridge off`. Then, in the
container, `systemctl --user disable --now hermes-bridge hermes-bridge-backend` as `hermes`.
