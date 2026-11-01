# Hermes API over Tailscale Funnel (for the Hermes phone app)

`#homelab` always runs `tailscaled` (`services.tailscale`, like the pi). Once `hermesFunnel.enable = true` (`modules/hosts/nixos-homelab.nix`) it also publishes Hermes:

```text
phone ──HTTPS──▶ Tailscale Funnel relay ──▶ tailscaled (homelab host, TLS ends here)
                                              └─▶ http://10.110.0.50:8642  Hermes API server (incus "hermes")
```

- **Outbound only.** tailscaled dials Tailscale, so no firewall port opens. `openFirewall` stays off: that only costs inbound UDP 41641, and NAT traversal still gives direct tailnet links in most cases, falling back to DERP relays otherwise. Funnel doesn't need it at all.
- **Only the API server is published.** The dashboard (9119) stays LAN-only at `hermes.home.arpa`. No subnet routes are advertised, so tailnet devices can't reach the Incus bridge either.
- **One lock: the API key.** Funnel is public, so anyone with the URL can reach Hermes, and Hermes rejects every request without `Authorization: Bearer <API_SERVER_KEY>`. The key is 64 hex chars, so that is enough, but don't share it.
- **Streaming works.** Funnel's proxy flushes `text/event-stream` as it arrives, so replies stream.
- **The `incus-hermes` unit configures Hermes.** It appends `API_SERVER_ENABLED`, `API_SERVER_HOST=0.0.0.0`, `API_SERVER_PORT` and an `API_SERVER_KEY` generated once to `~/.hermes/.env`, sets `gateway.multiplex_profiles: true`, and restarts the gateway once.
- **`hermes-funnel` is a reconcile job.** It runs on every deploy and every 2 min. It turns the Funnel on once the node is logged in and the tailnet allows Funnel, leaves it alone after that, and never fails a deploy. Check it with `journalctl -u hermes-funnel`.

Each step below needs you: a Tailscale login, an admin-console change, or a deploy.

## 1. Tailnet admin console (https://login.tailscale.com/admin), once
1. **DNS → MagicDNS: Enable.** Note your tailnet name, e.g. `tail1234.ts.net`, shown on the same page.
2. **DNS → HTTPS Certificates: Enable.** Funnel needs it.
3. **Access controls:** the policy must give homelab the `funnel` node attribute. New tailnets already have this. If your policy has no `nodeAttrs` entry with `"funnel"`, add:
   ```json
   "nodeAttrs": [
     { "target": ["autogroup:member"], "attr": ["funnel"] }
   ]
   ```
   Use `"target": ["tag:homelab"]` or the homelab owner's address instead if you want only this host to be allowed to use Funnel.

## 2. Deploy, then log homelab in to Tailscale (once)
Tailscale is already in the config, so deploy as usual:
```bash
nixos-rebuild switch --flake .#homelab --target-host surya@homelab.home.arpa --sudo
```
Then log in:
```bash
ssh -t homelab.home.arpa 'sudo tailscale up'
```
Open the printed URL and approve the machine. Optionally, in the admin console's **Machines** page, use **Disable key expiry** on `homelab` so it (and later the Funnel) doesn't drop off when the node key expires (180 days by default). Check with `ssh homelab.home.arpa tailscale status`.

## 3. Turn the Funnel on and deploy again
In `modules/hosts/nixos-homelab.nix`:
```nix
hermesFunnel = {
  enable = true;
  ...
};
```
Deploy again with the same command. `hermes-funnel` turns the Funnel on during the deploy, or within 2 minutes if the admin-console changes from step 1 are still propagating. Then:
```bash
ssh -t homelab.home.arpa 'tailscale funnel status'
# https://homelab.<tailnet>.ts.net (Funnel on)
# |-- / proxy http://10.110.0.50:8642
```
The first HTTPS request may take a few seconds while the certificate is issued, and the public DNS name can take up to 10 minutes to appear.

**Shortcut:** you can set `enable = true` before the first deploy and do one deploy plus `sudo tailscale up`. Until the login, `hermes-funnel` just logs "tailscale is NeedsLogin" every 2 minutes, then turns the Funnel on by itself within 2 minutes of the login.

## 4. Read the API key for the phone
```bash
ssh -t homelab.home.arpa 'sudo cat /var/lib/incus/hermes/api-server.env'
```
If `~/.hermes/.env` already had an `API_SERVER_KEY` (for example, migrated from the pi), that one is live and the generated one was not appended. Check with:
```bash
ssh -t homelab.home.arpa 'sudo incus exec hermes -- grep ^API_SERVER_KEY= /home/hermes/.hermes/.env'
```

## 5. Test
On homelab:
```bash
journalctl -u hermes-funnel -n 20       # "Funnel enabled ..." or "Funnel already serves ..."
curl -s http://10.110.0.50:8642/health
```
From anywhere, e.g. phone data or a machine off your LAN:
```bash
H=https://homelab.<tailnet>.ts.net
curl -s -o /dev/null -w '%{http_code}\n' $H/v1/capabilities                                    # 401: Hermes wants the key
curl -s -H "Authorization: Bearer <API_SERVER_KEY>" $H/v1/capabilities                          # 200 + JSON
curl -s -o /dev/null -w '%{http_code}\n' https://homelab.<tailnet>.ts.net:9119/                  # fails: nothing else is published
```
Then send a message from the phone and watch it stream.

## 6. Phone app
Settings in the Hermes app:
- **Server URL:** `https://homelab.<tailnet>.ts.net`
- **Hermes API key:** the `API_SERVER_KEY` from step 4
- **Cloudflare Access (optional):** leave empty

Tap Test & save.

**Other profiles.** With multiplexing, each named profile needs its own key in the container at `/home/hermes/.hermes/profiles/<name>/.env` (`API_SERVER_KEY=$(openssl rand -hex 32)`, then restart the gateway). Until then its `/p/<name>/` routes fail closed. Add the bot in the app with that profile name and key.

## Undo
- **Off right now:** `ssh -t homelab.home.arpa 'sudo systemctl stop hermes-funnel.timer && sudo tailscale funnel reset'`. The timer is back after the next deploy or reboot, so follow up with the next step.
- **Off for good:** set `hermesFunnel.enable = false`, redeploy, then run `ssh -t homelab.home.arpa 'sudo tailscale funnel reset'`. The reset is needed because `tailscaled` stays on and keeps the Funnel it already set up in `/var/lib/tailscale`; removing the job alone does not take it down. The API server then stays reachable only on the Incus bridge, still behind its key.
- **Tailscale itself:** remove the `services.tailscale` block to take homelab off the tailnet (`sudo tailscale logout` first to free the machine entry).
