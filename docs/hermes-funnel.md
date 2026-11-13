# Hermes dashboard over Tailscale Funnel

The homelab publishes the Hermes dashboard at `https://homelab.<tailnet>.ts.net/`.
Funnel is reachable from the public internet, including devices that are not in
the tailnet. The current setup uses Hermes's existing username and password;
this provider does not have MFA. [Hermes recommends](https://hermes-agent.nousresearch.com/docs/user-guide/features/web-dashboard)
using it only on trusted networks or behind a VPN, and using OAuth/OIDC for
public exposure. Prefer Tailscale Serve for tailnet-only access, or configure a
public-ready identity provider and disable password login. The LAN address
`http://hermes.home.arpa` continues to work.

```text
browser -> Tailscale Funnel (HTTPS) -> homelab tailscaled
                                     -> 10.110.0.50:9119 (Hermes dashboard)
```

The `hermes-funnel` service runs at boot/deploy and every two minutes. It reads
the node's actual Tailscale DNS name, writes the dashboard public URL, adds
only the host's `10.110.0.1` Incus bridge address to Hermes's trusted proxy
list, and restarts the dashboard when either setting changes. The trust entry
lets Hermes recognise the HTTPS scheme forwarded by tailscaled for secure
cookies. It checks that `/api/health` reports authentication enabled before
publishing the dashboard. Other already-configured trusted proxies are kept.

The previous phone API at `/` and the `/bridge` mount are retired. On the first
deploy, the reconciler removes the persisted `/bridge` route and replaces the
root target, while `incus-hermes` disables the old guest bridge units and phone
API listener. Hermes can enable that listener whenever an API key exists even
if `API_SERVER_ENABLED=false`, so provisioning also sets the explicit
`platforms.api_server.enabled: false` setting. The existing API and bridge keys
and guest data are retained for rollback; they are no longer provisioned or
published. No new key is minted.
The reconciler also retains the existing policy of removing public Funnel
listeners on ports other than 443.

## Prerequisites and deployment

The host must be logged into Tailscale, with MagicDNS, HTTPS certificates and
the Funnel node attribute enabled for it in the tailnet. See the
[Tailscale Funnel documentation](https://tailscale.com/docs/features/tailscale-funnel).
If the host is already using the previous Hermes Funnel, these prerequisites
are likely already satisfied.

Deploy from the machine that manages the homelab:

```bash
deploy .#homelab
```

If Tailscale is not logged in, run `sudo tailscale up` on the host and complete
its login. If the tailnet does not yet allow Funnel, enable HTTPS certificates
and grant the `funnel` node attribute in the Tailscale admin console. The job
logs failures and retries; it does not block a deploy while waiting for them.

## Verify

```bash
ssh homelab.home.arpa 'tailscale funnel status'
# Expect / -> http://10.110.0.50:9119 and no separate /bridge handler.
ssh homelab.home.arpa 'journalctl -u hermes-funnel -n 40 --no-pager'
ssh homelab.home.arpa 'curl -fsS http://10.110.0.50:9119/api/health | jq "{ok, auth_required}"'
# Expect ok: true and auth_required: true.
```

Open the HTTPS URL shown by `tailscale funnel status` from a browser outside
the tailnet and sign in with the existing dashboard credentials. Check that
chat and WebSockets work, and that an unauthenticated browser is sent to the
login page. If the dashboard is not published, inspect the job and dashboard
logs before changing any secrets:

```bash
ssh homelab.home.arpa 'sudo incus exec hermes -- sudo -u hermes -- env XDG_RUNTIME_DIR=/run/user/$(sudo incus exec hermes -- id -u hermes) journalctl --user -u hermes-dashboard -n 60 --no-pager'
```

The live dashboard credential remains in the `hermes-dashboard` Clan var and
in the guest's `~/.hermes/.env`; it is not rotated by this change. A stale
`HERMES_DASHBOARD_PUBLIC_URL` in that file is replaced with the Tailscale URL,
because that env value takes precedence over `config.yaml`.

## Turn it off

To stop public access immediately, stop the timer and remove the Funnel on the
host: `sudo systemctl stop hermes-funnel.timer` followed by
`sudo tailscale funnel reset`. To keep it off across deploys, also set
`hermesFunnel.enable = false` and deploy. Removing the job alone does not erase
Tailscale's persisted Funnel configuration.
