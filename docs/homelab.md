# Homelab: disks, backups, dashboards

How the `#homelab` (192.168.0.160) and `#raspberry-pi` (192.168.0.105) hosts look after
themselves. Everything here is declared in `modules/monitoring/` and
`modules/hosts/nixos-homelab.nix`; nothing is hand-installed.

## Disk health (SMART)

`nixos.diskHealth` (wired into `#nixos`, `#homelab`, `#raspberry-pi`) does two things:

- **`smartd`** runs continuously on autodetected drives. It uses `-a -n standby`, so a
  sleeping disk is never woken for a poll. Because no host runs an MTA and the journal
  rotates, `-M exec` points at a small hook that appends
  `<timestamp> <device> <failtype>: <message>` to `/var/lib/disk-health/alerts`
  (last 50 kept). Wall/mail/x11 notifications are off deliberately.
- **`disk-health.timer`** runs 5 minutes after boot and every 15 minutes after that. It
  calls `smartctl -j` per disk (`lsblk` type `disk`, minus `zram`), falling back to
  `-d sat` for USB bridges, and writes `/var/lib/disk-health/health.json`:

  ```json
  {
    "ok": true,
    "generated": "2026-10-27T14:25:39Z",
    "disks": [
      { "device": "/dev/nvme1n1", "model": "Samsung SSD 980 PRO 1TB",
        "smart": true, "health": "PASSED", "temperature": 38,
        "reallocated": 0, "pending": 0, "error": null }
    ],
    "failing": [],
    "alerts": []
  }
  ```

  `health` is `PASSED` / `FAILED` / `STANDBY` / `UNKNOWN`. A disk lands in `failing` when
  SMART reports failure or attributes 5 (reallocated sectors) or 197 (pending sectors) are
  non-zero. JSON is used instead of smartctl's text output because NVMe, SATA and
  USB-bridged drives all format that text differently.

Inspect by hand:

```bash
systemctl status disk-health.timer
sudo jq . /var/lib/disk-health/health.json
sudo smartctl -a /dev/nvme1n1
```

## Backups (restic)

Topology, chosen so no SSH key is copied between machines:

| Where | What |
|-------|------|
| pi | `services.restic.server` (rest-server) on TCP 8000, data in `/mnt/media/backups/restic`, `privateRepos = true` |
| homelab | pushes to `rest:http://192.168.0.105:8000/homelab/` |
| desktop | pushes to `rest:http://192.168.0.105:8000/nixos/` |

The repository name is `config.networking.hostName`, so each host's wiring is one module
import with no name to keep in sync.

- **Paths:** `/etc`, `/home`, `/var/lib` with `--one-file-system`.
- **Excluded:** caches, Trash, container images (`/var/lib/docker`, `/var/lib/containers`),
  the Incus storage pool and database, `/var/lib/flatpak`, `/nix`, `/var/cache`, `/var/tmp`.
  Container *definitions* stay in the backup via `/var/lib/incus`; the pool is
  re-creatable. Media under `/mnt/media` and Windows under `/mnt/windows` are separate
  filesystems and are not dragged in.
- **Schedule:** daily 03:30 with a 20-minute randomized delay, `Persistent = true`.
- **Retention:** `--keep-daily 7 --keep-weekly 4 --keep-monthly 6`, then
  `check --read-data-subset=5%`.

Every run (including a skip) writes `/var/lib/backup-status/<hostname>.json`:

```json
{ "name": "homelab", "ok": true, "result": "success", "exitCode": "success",
  "at": "2026-10-27T03:31:12Z" }
```

The name is the host, not the backup set, because every machine's set is called
`default`.

### First-time setup

Passwords never enter the flake. On the pi, first boot seeds
`/var/lib/restic-rest/htpasswd` and `/var/lib/restic-rest/clients.env` (root-only,
plaintext copies so you can copy them to clients without scraping the journal).

1. On the pi, read the credentials:

   ```bash
   sudo cat /var/lib/restic-rest/clients.env
   ```

2. On each client, create `/var/lib/restic-backups/env` (mode 0600) with that host's
   lines plus a shared repository password:

   ```bash
   RESTIC_PASSWORD=<long random string, same on every client>
   RESTIC_REST_HOMELAB_USERNAME=homelab
   RESTIC_REST_HOMELAB_PASSWORD=<from clients.env>
   ```

   The desktop uses the `NIXOS` pair instead of `HOMELAB`.

3. Until the file exists the unit **skips** via `ExecCondition` and records
   `result: "unknown"` — the dashboard says "not configured" rather than showing a stale
   success. Run one manual backup to seed the repository:

   ```bash
   sudo systemctl start restic-backups-default.service
   sudo journalctl -u restic-backups-default.service -n 40
   ```

Restore (into a scratch directory, never over live state):

```bash
sudo install -d -m 0700 /tmp/restore
sudo systemctl stop restic-backups-default.timer
sudo -E env $(sudo grep RESTIC_ /var/lib/restic-backups/env | xargs) \
  restic restore latest --target /tmp/restore --include /etc
```

## Dashboards and alerting

All three already exist; the monitoring modules only feed them.

| Surface | URL | Note |
|---------|-----|------|
| Homepage | `http://home.home.arpa` | `customapi` widgets: Apps, Services, Processes, Temperatures, Disk health, Backups, AdGuard |
| Gatus | `http://status.home.arpa` | adds `smart-disks` and `backups`, both `[BODY].ok == true` |
| Netdata | `http://netdata.home.arpa` | already present, per-second metrics for the whole host |

The two feeds come from the loopback-only `homelab-stats` service on `127.0.0.1:8793`
(`modules/hosts/homelab-stats/homelab_stats.py`):

- `GET /disk.json` — one row per drive (`asleep`, `no SMART`, or `<HEALTH> · <temp>°C`),
  plus the last two smartd alerts.
- `GET /disk/health.json` — `{ok, disks, failing}`; a *missing* snapshot is red, because
  silence would otherwise look healthy.
- `GET /backups.json` — one row per host: `<result> · <timestamp>`.
- `GET /backups/health.json` — `{ok, hosts, failing}`.

Gatus has no notifier configured yet (`services.gatus.environmentFile` is the hook for
one). Until it does, a red check is only visible on the status page.

## Nutify (UPS monitoring)

`incus-nutify` provisions an Incus OCI container from the pinned
`docker:dartsteven/nutify@sha256:dad34267…` digest on `10.110.0.103:5050`, reached
as `http://nutify.home.arpa` through Caddy (the pi's AdGuard rewrite points that
name at `192.168.0.160`). It runs in *Remote NUT Only* mode: no local USB driver,
so it never competes with `apcupsd`/gridwatch on the desktop. Nothing is wired to a
UPS yet — the target is entered in Nutify's own wizard, which writes
`/etc/nut` into the container volume (`/var/lib/nutify/etc-nut`).

State that survives a unit restart or a digest bump:

| Path | Holds |
|------|-------|
| `/var/lib/nutify/instance` | SQLite instance + web-app config |
| `/var/lib/nutify/logs` | app logs |
| `/var/lib/nutify/etc-nut` | NUT config written by the wizard |
| `/var/lib/nutify/secrets.env` | `SECRET_KEY`, generated once, never rotated |

The image's entrypoint starts `upsd`/`upsmon` and validates `/etc/nut` *before* the
web app, so the mount exists with an empty `ups.conf` and `MODE=none` from the first
boot. A brand-new instance answers `302` (login) rather than `200`; the Gatus check
therefore accepts both, and it only proves the container serves — not that a UPS is
reachable.

A single UPS is exposed to exactly one host. Point Nutify at a NUT server that
already exports one; do not point it at the desktop's UPS while gridwatch owns it.

Inspect it from the host:

```bash
sudo incus list nutify
sudo incus exec nutify -- env | grep NUT
sudo incus exec nutify -- cat /etc/nut/ups.conf
```
