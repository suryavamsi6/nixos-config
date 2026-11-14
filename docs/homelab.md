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

## Incus application updates

`incus-app-update.timer` runs every Sunday at 04:30 (plus up to 20 minutes) and
rebuilds allowlisted Incus OCI instances onto newer upstream images. The allowlist
lives in `modules/services/incus-auto-update.nix`; the updater
(`scripts/incus-app-update.py`) touches nothing that is not described there.

It skips gated units, and for an in-guest unit it skips work when the app says
nothing is pending. Otherwise, for every instance, it verifies in this order:

1. the instance is running, and its declared host-backed disks still match the
   exact device, source and mount path the config expects;
2. each of those paths is a live mount inside the container and its required
   files exist;
3. the data tree contains only plain files and directories, so a copy cannot
   silently follow a link;
4. every HTTP health URL answers 2xx/3xx;
5. the upstream image resolves to a fingerprint, and — when `oci.version` is a
   real version and the app reports its running version — it is not a downgrade.

Only then does it stop the instances in a unit, create a `pre-update-<UTC>`
snapshot (30-day expiry), copy each host data directory to
`/var/lib/incus-auto-update/backups/<snapshot>-data/`, rebuild each instance onto
the resolved fingerprint, start it, and re-check health and mounts. A unit is
rebuilt as a set, so paired instances (Homelable's backend and frontend) never
run different builds.

Currently covered: MCPHub, Reactive Resume, Grimmory (Booklore application
container), Qdrant, Bifrost, Nutify, Hermes, OpenBot, and Homelable behind a
gate.

Hermes and OpenBot are not OCI instances: their units provision an Ubuntu guest
and the app installs itself inside it, so a rebuild would destroy the install.
Those two are `in-guest` units. Instead of stop/snapshot/rebuild they run the
app's own updater inside the container — `hermes update --yes`, and
`openbot update` when `openbot status` reports a release is ready — then
re-check health. `hermes update --check` is read-only and decides whether
anything is pending. An in-guest unit is never stopped, so a failed run leaves
the app running with `pending.json` for review rather than a stopped container.

**Never updated by this timer:** the MariaDB containers (`booklore-db`, and the
pi's `mariadb`), and Home Assistant OS, which is a VM: update it from inside
Home Assistant (`ha os update` / Settings → Updates), because there is no image
to rebuild onto. Homelable needs a migration first: its SQLite database lives
in the instance root filesystem, so a rebuild would discard it. The updater
skips the Homelable unit until `/var/lib/incus-auto-update/homelable-enabled`
exists. Run `scripts/homelable-migrate-data.sh`, move the database onto a host
disk, verify it, then create that file.

Some containers are not declared in this repository and are therefore outside
the allowlist: `litellm` (its `/app/config.yaml` lives in the container root
filesystem, so a rebuild would erase the model config), `open-design`,
`nanomuse` (stopped), and `lens` (a Docker host, not a pinned app). Adopting one
means first declaring it as a module here, or at minimum moving its config onto
a host disk, before adding it to the allowlist.

Some services are pinned by digest in this repository (Qdrant, Bifrost, Nutify,
Reactive Resume, Booklore, Homelable). The pins only seed a fresh install: the
bootstrap units create an instance once and never recreate it, so an automatic
rebuild leaves the pin behind the running container. Treat a pin as the
known-good floor for reinstalls, and update it when you next touch that service.

The local copies are **not** an off-host backup, and they can contain
credentials; restic is still the backup that matters. Snapshots expire after 30
days and the copies need manual retention management. Passing an HTTP health
check does not prove every feature works.

Before trusting the timer, run the read-only check — it prints what it would do
and changes nothing:

```bash
sudo systemctl start incus-app-update-dryrun
journalctl -u incus-app-update-dryrun -n 50 --no-pager
```

Then update one unit by hand: `sudo systemctl start incus-app-update` picks up
everything pending; to test a single unit, run the service's `ExecStart` with
`--only <unit>` instead.

The unit runs with a minimal `PATH` holding only the Incus CLI and `skopeo`
(which Incus shells out to for OCI remotes). If a future Incus feature needs
another binary, add it to `incusPath` in the module; `command not found` inside
the journal means exactly that, and a login shell will not reproduce it.

To inspect failures, use `journalctl -u incus-app-update.service` and read
`/var/lib/incus-auto-update/pending.json` as root. If a rebuild or health check
failed, the unit is left stopped: assess the instance snapshot and the matching
`*-data` copy together before restoring, because an application upgrade may have
migrated data. Do not remove `pending.json` until the state is understood. To
suspend scheduled runs, stop the timer or create
`/var/lib/incus-auto-update/disabled`; deleting that file re-enables them.

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

2. That env file is a Clan var, not a file to write by hand; adopt it with the
   repository password supplied on the command line:

   ```fish
   set PW (head -c 32 /dev/urandom | base64 -w0)   # save this in 1Password first
   env RESTIC_REPO_PASSWORD=$PW ./scripts/clan-adopt-secrets.sh homelab  # HOMELAB pair
   env RESTIC_REPO_PASSWORD=$PW ./scripts/clan-adopt-secrets.sh nixos    # NIXOS pair
   ```

   (`PW=$(…) cmd` and `VAR=v cmd` are bash-isms; the user shell is fish, where they are
   `set PW (…)` and `env VAR=v cmd`. `openssl` is not on PATH either — coreutils `base64`
   over `/dev/urandom` is equivalent.)

   It is decrypted to `/run/secrets` before sysinit, so there is nothing to create on
   the client. Do **not** write `/var/lib/restic-backups/env` by hand any more — the
   migration unit only records that it was migrated, and the var is the source of truth.
   (`RESTIC_REST_<HOST>_PASSWORD` comes from the pi's `restic-htpasswd/clients-env`, which
   is already adopted, so only the repository password is new information.)

3. Until the var exists the unit **skips** via `ExecCondition` and records
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
sudo -E env $(sudo grep RESTIC_ /run/secrets/per-machine/$(hostname)/restic-client/env |
  xargs) restic restore latest --target /tmp/restore --include /etc
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
so it never competes with `apcupsd` on the desktop. Nothing is wired to a
UPS yet — the target is entered in Nutify's own wizard, which writes
`/etc/nut` into the container volume (`/var/lib/nutify/etc-nut`).

State that survives a unit restart or a digest bump:

| Path | Holds |
|------|-------|
| `/var/lib/nutify/instance` | SQLite instance + web-app config |
| `/var/lib/nutify/logs` | app logs |
| `/var/lib/nutify/etc-nut` | NUT config written by the wizard |
| `/var/lib/nutify/secrets.env` | legacy copy of the `SECRET_KEY` that now lives in the Clan vars store |

The image's entrypoint starts `upsd`/`upsmon` and validates `/etc/nut` *before* the
web app, so the mount exists with an empty `ups.conf` and `MODE=none` from the first
boot. A brand-new instance answers `302` (login) rather than `200`; the Gatus check
therefore accepts both, and it only proves the container serves — not that a UPS is
reachable.

A single UPS is exposed to exactly one host. Point Nutify at a NUT server that
already exports one; do not point it at the desktop's UPS, which apcupsd owns.

Inspect it from the host:

```bash
sudo incus list nutify
sudo incus exec nutify -- env | grep NUT
sudo incus exec nutify -- cat /etc/nut/ups.conf
```

## Where the homelab services live

The host file `modules/hosts/nixos-homelab.nix` is now host *plumbing*: hardware import,
hostname, state version, firewall, Incus host setup, the Postgres instance the
containers share, Tailscale and the Funnel job. Everything that is a service lives in
`modules/services/` as a `flake.modules.nixos.<name>` deferred module, and the host
enables one by listing it in its `imports`.

There is no `.enable` flag on these modules. Enabling is the import; that keeps a
single source of truth and matches how `nixos.cliproxyapi` and the rest of the registry
already work. If a future host needs one of them, add the import — do not copy the
block.

| Module | Provides |
|--------|----------|
| `netdata` | Agent on `127.0.0.1:19999`, served as `netdata.home.arpa` |
| `gatus` | Uptime checks + SQLite history, `status.home.arpa` |
| `searxng` | Metasearch on `:8888`, `search.home.arpa` |
| `homepage` | Dashboard + the `homelab-stats` feed (`:8793`, `:8082`) |
| `grok-oauth-proxy` | SuperGrok as an OpenAI-compatible API (`:56121`) |
| `caddy` | The vhost table — the LAN door for every name above |
| `openbot` | Provisioning oneshot for the OpenBot guest |
| `reactive-resume` | Incus OCI guest on `10.110.0.80` |
| `nutify` | Incus OCI guest on `10.110.0.103` (see above) |
| `qdrant` | Incus OCI guest on `10.110.0.102` |
| `bifrost` | Incus OCI guest on `10.110.0.100` (AI gateway) |
| `hermes` | Incus guest + authenticated dashboard over Tailscale Funnel |
| `booklore` | Incus guests `10.110.0.60` (MariaDB) and `10.110.0.61` (app) |
| `homelable` | Two-guest canvas on `10.110.0.91` |
| `mcphub` | MCP gateway guest, `mcp.home.arpa` |
| `haos` | Home Assistant OS as an Incus *VM* |

The extraction was mechanical and gated: `nix eval --raw
.#nixosConfigurations.homelab.config.system.build.toplevel.drvPath` had to return the
same store path before and after each move, so a changed `drvPath` meant
"you moved something you did not mean to move", not "the refactor is fine". Live data was
never touched: every `/var/lib/incus/*` bind mount and every guest IP is verbatim.

Deploying changes to this host from the desktop, without a shell on it:

```bash
deploy .#homelab          # build locally, activate over SSH
deploy .#homelab --dry-activate   # print the profile, touch nothing
clan machines update homelab      # the same deploy node, via Clan
```

A failed remote activation fails the whole `deploy` run; it does not leave you
guessing. Both frontends read the same `modules/clan/` nodes, so they cannot drift.

## Secrets (Clan vars)

Every credential the homelab and the pi need is a **Clan var**, not a file written by a
first-boot `*-secrets` oneshot. `modules/clan/secrets.nix` declares one generator per
secret; the consumer reads

```nix
config.clan.core.vars.generators.qdrant-api-key.files.api-key.path
```

which resolves to `/run/secrets/per-machine/<machine>/<generator>/<file>` — tmpfs,
decrypted by Clan's `setupSecrets` activation script (run after `specialfs` mounts
`/run`). Note there is **no** `age-decrypt-secrets.service`: Clan only creates such a
unit when `systemd.sysusers.enable` or `services.userborn.enable` is on, and neither is
here, so the activation script is the whole mechanism. Do not add
`requires`/`after = [ "age-decrypt-secrets.service" ]` to a consumer unit — it does not
exist, and systemd then refuses to start the consumer with
`Unit age-decrypt-secrets.service not found`. Ordering against the *per-generator*
`<generator>-secrets.service` (e.g. `qdrant-secrets.service`) is enough and is what the
existing units do.

The ciphertext lives **outside this repo** (`flake.clan.vars.settings.age.externalStore`,
`$CLAN_AGE_STORE_DIR`, `~/clan-secrets` here), because the flake is public. That has one
operational consequence:

```bash
clan vars upload homelab          # push ciphertext before a deploy that changes a secret
clan vars upload raspberry-pi
```

`deploy .#homelab` does **not** upload vars — deploy-rs knows nothing about them, and with
an external store the ciphertext is not in the system closure either. A deploy that
changes a secret without an upload activates with the *old* value.

`CLAN_AGE_STORE_DIR` must be exported for every `clan vars` call; unset, `clan vars check`
fails with "vars.settings.age.externalStore is enabled, but CLAN_AGE_STORE_DIR is not set."

### Every generator is adopt-only

No generator mints a value. `clan vars generate` on a missing generator prints the
adoption command and exits non-zero, because all of these credentials are live and
entangled:

| Rotating | Breaks |
|----------|--------|
| `qdrant-api-key` | Bifrost's vector-store config and Gatus' probe |
| `bifrost-encryption-key` | every secret Bifrost has stored |
| `bifrost-db-password` | Bifrost's Postgres role (needs `ALTER ROLE`, not a boot action) |
| `reactive-resume-*` | the Postgres role, every session, or stored encrypted fields |
| `booklore-*` | the app↔MariaDB pairing (`MYSQL_ROOT_PASSWORD` is only read at first init) |
| `hermes-dashboard` | dashboard and Desktop sign-in |
| `grok-oauth` | Caddy's `/grok` injection and Gatus' authenticated check |
| `restic-htpasswd` / `restic-client` | every client's nightly push (401 into an unrecoverable repo) |
| `homepage-vars` | the dashboard widgets (and the values are human-supplied) |

Adoption is one script:

```bash
export CLAN_AGE_STORE_DIR=$HOME/clan-secrets
./scripts/clan-adopt-secrets.sh --list          # what is missing, and from where
./scripts/clan-adopt-secrets.sh raspberry-pi    # restic htpasswd + client list (root ssh, never prompts)
./scripts/clan-adopt-secrets.sh homelab         # grok-oauth + searx (ssh + sudo, prompts once)
./scripts/clan-adopt-secrets.sh nixos           # this workstation's restic client env

# The two client targets also need the repository password, which lives nowhere on disk:
env RESTIC_REPO_PASSWORD=$PW ./scripts/clan-adopt-secrets.sh homelab
env RESTIC_REPO_PASSWORD=$PW ./scripts/clan-adopt-secrets.sh nixos
```

`restic-client/env` is **not** adopted from `/var/lib/restic-backups/env`. That path
never existed on either host: the topology in `modules/monitoring/backups.nix` says each
client pushes to `rest:http://192.168.0.105:8000/<hostname>/`, but no client env file was
ever provisioned, and `restic` was never initialised on the pi — `/mnt/media/backups/restic/`
contains no per-host repository. So the var is assembled from its two halves instead:
`RESTIC_REST_<HOST>_{USERNAME,PASSWORD}` come from the pi's `restic-htpasswd/clients-env`
(already in the store), and `RESTIC_PASSWORD` is supplied by the operator. The script
refuses rather than minting one: a fresh password would not match what any repo was
initialised with, and the nightly unit skips cleanly on its own
(`ExecCondition = test -r <envFile>`) until the var exists.

The two that use `sudo` ask for the password once, reading it from `/dev/tty`
explicitly, then pipe it to `sudo -S` per host. The password goes in through a pipe and
the file comes out through a temp file, so nothing needs a terminal on stdin — which is
what makes the script usable from a wrapper or a command substitution.

Three obvious alternatives all fail, quietly enough to look like a permissions problem:
`sudo -v` caches its credential per login *session* and ssh shares no session between two
connections, so "prime, then read" leaves the second connection unauthenticated;
`ssh -t` inside `$(…)` gives sudo a pty to prompt on but a pipe to write to, and deadlocks;
and `ssh -T` with the terminal left on stdin never reads a password at all, because inside
`$(…)` fd 0 is the substitution's pipe. That last one hangs indefinitely while looking
like it is working.

Everything it writes is read back and compared before it reports success. It is idempotent and
normalising: `incus config show --expanded` emits `environment.KEY: value`, which it rewrites to
`KEY=value` — the shape the consumers grep for — and it strips CR (an ssh pty injects them, and a
stray `\r` inside a bcrypt hash fails authentication with no useful error). It refuses to store a
file that is missing an expected key rather than adopting a partial secret. Re-running an adopted
target prints `already adopted, unchanged` and writes nothing.

`homepage-vars` is the one generator with a prompt. The widget logins are human-supplied,
so instead of a file to edit:

```bash
clan vars set homelab homepage-vars/secrets < /var/lib/homepage-dashboard-env/secrets.env
clan vars generate homelab -g homepage-vars   # fills secrets-env from the persisted prompt
```

`clan vars generate` on a machine that still has missing prompts crashes with
`termios.error: (25, 'Inappropriate ioctl for device')` in a non-TTY, so answer prompts
with `clan vars set`, not `generate`.

### The migration bridge

Every old `*-secrets` unit is still installed, but its "write if absent" branch is
inverted: it now only touches `/var/lib/<svc>/.migrated-to-clan` and never rewrites the
file. The old file stays on disk, so reverting one line in the service module is a
complete rollback. Delete the units in a separate commit once a week of boots has been
clean.

Two copies remain deliberately outside `/run/secrets`:

- `/var/lib/restic-rest/htpasswd` — `services.restic.server` runs with
  `PrivateUsers=true`, and a root-owned file under `/run/secrets` appears as `nobody`
  inside that user namespace. The activation copies the var into place.
- `/var/lib/homepage-dashboard-env/secrets.env` — Homepage runs as a `DynamicUser` with no
  stable uid, so `EnvironmentFile` cannot come from `/run/secrets` directly. The var is
  installed at mode 0644, which is what the old hand-managed file was.
