# Plan: move `nixos-config` to a Clan + deploy-rs fleet layout

> **Status:** ready for review. Decisions locked (§1). Nothing here has been executed —
> this is a plan; every step names its own equivalence gate.
>
> Grounded in: Clan 26.05 (`clan-core` main, `flakeModules/clan.nix`, `modules/clan/module.nix`),
> deploy-rs v1.0.0 (`1cec0527`, 2026-10-19), and a read-only inventory of this repo.

## 1. Decisions (locked)

| Question | Answer |
|---|---|
| Scope | **Whole repo** — all five hosts become Clan machines (`nixos`, `mango`, `homelab`, `raspberry-pi`, `macbook-air`). |
| Secrets | **Clan vars** (`vars.settings.secretStore = "age"`), replacing the plain `/var/lib/*/secrets.env` files. |
| Deployment | **deploy-rs first** (workstation → host, magic rollback), then `clan machines update` as the everyday path. |
| Migration style | **Incremental, equivalence-gated**: each step must produce an identical `system.build.toplevel.drvPath` (or a reviewed, intentional diff) before the next step lands. |

Non-goals: reinstall/repartition any host, disko, container tag bumps, secret rotation
beyond relocating storage, changing the desktop workflow (`nh os switch` stays for
`#nixos`/`#mango`/`#macbook-air`).

## 2. Target architecture

### 2.1 Layer map

| Concern | Today | After |
|---|---|---|
| Composition | `flake-parts` `mkFlake`, `imports = [ ./modules ]` | unchanged (`flake-parts` stays load-bearing) |
| Reusable config | `options.flake.modules.{nixos,homeManager,darwin}.*` deferred modules (21 `mkOption` sites) | unchanged — **this is the migration's reusable unit** |
| Host composition | `config.flake.nixosConfigurations.<host> = inputs.nixpkgs.lib.nixosSystem { modules = with config.flake.modules; [...] }` inside each host file | each host file registers `flake.modules.nixos.<host>`; `modules/clan/machines.nix` maps machines → those registry entries |
| Machine eval | our five `nixosSystem`/`darwinSystem` calls | Clan evaluates them: `nixosConfigurations` / `darwinConfigurations` come from `flake.clan` |
| Fleet inventory | none | `clan.inventory.machines.<host>` (tags, `machineClass`, `deploy.targetHost/buildHost`) + `clan.inventory.instances` (services: `admin`, `sshd`, `users`, `certificates`, `internet`, `p2p-ssh-iroh`) |
| Secrets | imperative `*-secrets` units writing `/var/lib/.../*.env` | `clan.core.vars.generators.*` (`age` recipients per machine) |
| Deploy | SSH + `nixos-rebuild` on the host | `deploy .#homelab` (deploy-rs) / `clan machines update <host>` |
| Checks | none | `flake.checks` ← `deploy-rs.lib.<system>.deployChecks self.deploy` |

### 2.2 Ownership rules (the invariant that keeps this sane)

1. `modules/**` owns *reusable* config and keeps declaring `options.flake.modules.<class>.<name>`.
2. `modules/hosts/<host>.nix` owns *host identity only*: `hostname`, `hostPlatform`, hardware
   import, `stateVersion`, monitor/disk specifics — and **nothing that another host could use**.
3. `modules/clan/inventory.nix` owns *fleet facts*: which hosts exist, their class, tags,
   deploy targets.
4. `modules/clan/deploy.nix` owns *how code reaches a host* (deploy-rs nodes).
5. `modules/clan/vars.nix` owns *secrets* (generators + recipients).
6. `modules/services/<name>/` owns one service each, extracted from `nixos-homelab.nix`.

## 3. Flake inputs and wiring

`flake.nix` — add two inputs. Pin them onto **our** nixpkgs, not the other way around
(Clan requires an `_class`-aware nixpkgs, which our `nixos-unstable` pin has; the template's
`nixpkgs.follows = "clan-core/nixpkgs"` would silently move our pin):

```nix
inputs.clan-core.url = "github:clan/clan-core";           # or https://git.clan.lol/clan/clan-core/archive/main.tar.gz
inputs.clan-core.inputs.nixpkgs.follows = "nixpkgs";
inputs.clan-core.inputs.nix-darwin.follows = "nix-darwin";
inputs.clan-core.inputs.flake-parts.follows = "flake-parts";

inputs.deploy-rs.url = "github:serokell/deploy-rs";
inputs.deploy-rs.inputs.nixpkgs.follows = "nixpkgs";
```

`modules/default.nix` — add `./clan` to the import list (after `./hosts`).
`modules/clan/default.nix` (new, flake-parts module):

```nix
{ ... }:
{
  imports = [ inputs.clan-core.flakeModules.default ./inventory.nix ./machines.nix ./vars.nix ./deploy.nix ];
  # Registry entries must be visible to machine modules (see §4.2).
  flake.clan.specialArgs.flakeModules = config.flake.modules;
}
```

`clan.specialArgs` is a real Clan option (`modules/clan/top-level-interface.nix:155`), and
Clan passes it to every machine's `nixosSystem`/`darwinSystem` as `specialArgs`
(`modules/clan/module.nix:67-70`). This is what lets host files keep using
`with flakeModules; [ ... ]` after they stop calling `nixosSystem` themselves.

## 4. Machine definitions

### 4.1 `modules/clan/inventory.nix`

```nix
{
  flake.clan = {
    meta.name = "homelab";
    meta.domain = "home.arpa";        # matches the existing `*.home.arpa` Caddy hostnames

    inventory.machines = {
      homelab       = { tags = [ "server" "lan" ]; deploy.targetHost = "homelab.home.arpa"; };
      raspberry-pi  = { tags = [ "server" "pi" ];  deploy.targetHost = "pi.home.arpa"; };
      nixos         = { tags = [ "desktop" ]; };
      mango         = { tags = [ "desktop" "experimental" ]; };
      macbook-air   = { machineClass = "darwin"; tags = [ "laptop" ]; };
    };
  };
}
```

`machineClass` defaults to `"nixos"`; only `macbook-air` needs `"darwin"`
(`modules/clan/inventory.nix` option at `clan-core/modules/clan/inventory.nix:274`).
`deploy.targetHost` is for `clan machines update`; deploy-rs keeps its own `hostname` (§5).

### 4.2 `modules/clan/machines.nix`

This file holds exactly the composition lists that today live in the `nixosSystem { ... }`
wrappers, now addressed as deferred modules:

```nix
{ config, ... }:
let
  m = config.flake.modules;
in
{
  flake.modules.nixos.hyprlandHost = { flakeModules, inputs, pkgs, ... }: {
    imports = with flakeModules; [ nixos.hardwareHyprland nixos.hyprland /* … the 40 entries from nixos-hyprland.nix:10-52 … */ ];
    nixpkgs.hostPlatform = "x86_64-linux";
    networking.hostName = "relic";
    # home-manager wiring moved out of the nixosSystem wrapper (nixos-hyprland.nix:61-76):
    home-manager = { useGlobalPkgs = true; useUserPackages = true; backupFileExtension = "bak";
      sharedModules = with flakeModules; [ homeManager.shell /* … */ ]; };
  };

  flake.clan.machines = {
    nixos        = { imports = [ m.nixos.hyprlandHost ]; };
    mango        = { imports = [ m.nixos.mango ]; };            # nixos-mango.nix:83-100 hoisted the same way
    homelab      = { imports = [ m.nixos.homelab ]; };          # nixos-homelab.nix:27-29 inline deferredModule
    raspberry-pi = { imports = [ m.nixos.raspberryPi ]; };      # nixos-raspberry-pi.nix host body
    macbook-air  = { imports = [ m.darwin.macbookAir ]; };
  };
}
```

`flake.clan.machines.<name>` is `types.attrsOf types.deferredModule`
(`modules/clan/top-level-interface.nix:162`), so plain registry entries compose directly.

### 4.3 Three fixes every machine needs (Clan does not pass them)

Clan calls `nixpkgs.lib.nixosSystem { modules = [...]; specialArgs = { inherit clan-core; } // specialArgs; }`
— **no `system` argument and no per-host `specialArgs`** (`clan-core/modules/clan/module.nix:54-70`).

1. **`nixpkgs.hostPlatform` per machine.** Today it comes from `nixSystem { system = "…"; }`
   (`nixos-hyprland.nix:5,8`, `nixos-mango.nix:5,8`, `nixos-raspberry-pi.nix:5,8`,
   `nixos-homelab.nix:17,20`). Under Clan it must be set inside the module:
   `nixpkgs.hostPlatform = "x86_64-linux"` / `"aarch64-linux"` / `"aarch64-darwin"`.
   `homelab-hardware-configuration.nix:40` and `darwin-macbook-air.nix:24` already do this;
   `nixos`, `mango`, `raspberry-pi` do not.
2. **Drop the `system` specialArg.** Only real consumer is `modules/desktop/zen.nix:51`
   (`inputs.zen-browser.packages.${system}.twilight-unwrapped`) → change to
   `inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.twilight-unwrapped`
   (the pattern every other module already uses, e.g. `modules/hyprland/wm.nix:37`).
3. **Keep `inputs` available.** Clan's `specialArgs` covers it (§3), so `inputs` module args
   used across `modules/**` keep working; no per-host `extraSpecialArgs` needed for the
   Home Manager registry either, because `home-manager.extraSpecialArgs` moves into the host
   module next to the `home-manager` block.

### 4.4 darwin caveat (be explicit)

`macbook-air` becomes a `machineClass = "darwin"` machine, so Clan generates
`darwinConfigurations.macbook-air`. Two limits to plan around:

- **Clan vars do not activate on darwin** the way they do under systemd. The macbook keeps
  its current secret story (nothing to migrate there today — it has no `/var/lib` secrets).
- `darwin-rebuild switch --flake .#macbook-air` keeps working because Clan re-exports
  `darwinConfigurations` at the flake top level (`flakeModules/clan.nix:100-107`).

## 5. deploy-rs nodes (`modules/clan/deploy.nix`)

deploy-rs has **no** upstream flake-parts output (`flakeModules*` does not exist at `1cec0527`),
so the glue is ~20 lines here.

```nix
{ self, inputs, lib, ... }:
let
  drs = inputs.deploy-rs.lib;
in
{
  flake.deploy.nodes = {
    homelab = {
      hostname = "homelab.home.arpa";
      sshUser  = "<existing admin user>";        # confirm: nix eval .#nixosConfigurations.homelab.config.users.users --apply builtins.attrNames
      sshOpts  = [ "-T" ];
      profiles.system = {
        user = "root";
        path = drs.x86_64-linux.activate.nixos self.nixosConfigurations.homelab;
      };
      autoRollback = true; magicRollback = true;   # defaults, stated for intent
      confirmTimeout = 60; activationTimeout = 600;
      fastConnection = false;                     # use target substituters first
      remoteBuild = false;                        # workstation builds, then `nix copy`
    };

    raspberry-pi = {
      hostname = "pi.home.arpa";
      sshUser  = "suryavamsi";                    # as configured in nixos-raspberry-pi.nix
      profiles.system.user = "root";
      profiles.system.path = drs.aarch64-linux.activate.nixos self.nixosConfigurations.raspberry-pi;
      remoteBuild = true;                         # aarch64 target: build on the Pi (ssh-ng), never emulate on x86_64
      fastConnection = false; magicRollback = true; autoRollback = true;
    };

    macbook-air = {                               # optional; darwin activator, needs HOME=/var/root
      hostname = "macbook-air.home.arpa";
      sshUser  = "suryavamsi";
      profiles.system.path = drs.aarch64-darwin.activate.darwin self.darwinConfigurations.macbook-air;
      magicRollback = false;                      # darwin has no `switch-to-configuration` confirmation path
    };
  };

  flake.checks = builtins.mapAttrs (_system: deployLib: deployLib.deployChecks self.deploy) drs;
}
```

Facts this relies on (verified in `1cec0527`): activation = `nix-env -p /nix/var/nix/profiles/system --set <store>`
then `"$PROFILE/bin/switch-to-configuration" switch`; rollback = `nix-env --rollback` + rerun the
previous generation; checks run automatically (`nix flake check`) unless `-s`/`--skip-checks`.
There is no `--checks` flag and no `activationStrategy` node option — use
`--dry-activate` / `--boot` / `--test` on the CLI instead.

Desktops (`nixos`, `mango`) deliberately get **no** deploy node: they stay local
(`nh os switch`), which matches how they are actually used.

## 6. Secrets → Clan vars

### 6.1 Model

```nix
# modules/clan/vars.nix
{
  flake.clan.vars.settings = {
    secretStore = "age";
    recipients.default = [ "age1<personal-key>" ];            # added by `clan vars …`/`clan init`
    recipients.hosts.pi = [ "age1<personal-key>" "age1<pi-key>" ];
  };
}
```

Prefer the machine's own key for machine-only secrets so a lost laptop does not lock out the
fleet; keep the admin key in `recipients.default` for break-glass.

### 6.2 Generator mapping (from the inventory of `nixos-homelab.nix`)

| Current file | Lines | Generator | `neededFor` | Note |
|---|---|---|---|---|
| `/var/lib/qdrant-secrets/api-key` | 981, 1038-1058 | `qdrant-api-key` | `incus-startup` / qdrant unit | also read by Bifrost (1120) |
| `/var/lib/bifrost/secrets.env` | 1112-1119 | `bifrost-secrets` | `bifrost` container unit | split per key |
| `/var/lib/incus/hermes/dashboard.env` | 1459-1468 | `hermes-dashboard` | hermes unit | copied into container `~/.hermes/.env` |
| `/var/lib/incus/hermes/bifrost-vk.env` | 1515-1555 | `hermes-bifrost-key` | hermes unit | keep "minted key" warning semantics |
| `/var/lib/incus/hermes/api-server.env` | 1613-1631 | `hermes-api-server` | hermes unit | |
| `/var/lib/incus/booklore/booklore.env` | 1774-1791 | `booklore-db` | booklore units | DB + MySQL root password |
| `/var/lib/grok-oauth-proxy/secrets.env` | 2211-2250 | `grok-oauth` | `grok-oauth-proxy` | consumed by Caddy env (3031) + Gatus (2305) |
| `/var/lib/searx/secret.env` | 3096-3119 | `searx-secret` | `searx` | |
| `/var/lib/reactive-resume/secrets.env` | 3272-3279 | `reactive-resume` | resume unit | + `flags.env` stays plain (not secret) |
| `/var/lib/nutify/secrets.env` | 3387-3395 | `nutify` | nutify unit | |
| `/var/lib/restic-rest/htpasswd`, `clients.env` | backups.nix:36-100 | `restic-htpasswd` | `restic-rest` | shared infra: consumed by homelab + desktop clients |
| `/var/lib/restic-backups/env` | backups.nix:154 | `restic-client` | `restic-backups` | per-host |
| `/var/lib/homepage-dashboard-env/secrets.env` | 2331, 2759-2798 | `homepage-vars` | homepage unit | **human-supplied**: `prompt.type = "hidden"; prompt.persist = true;` |
| Caddy internal CA (`/var/lib/caddy/.../root.crt`) | 3052-3054, but **not** a secret to manage | — | — | leave as-is; desktop trusts it via `nixos-hyprland.nix:100-111` |

Each generic generator follows the shape already used upstream
(`clan-core/clanServices/admin/root-password.nix`):

```nix
clan.core.vars.generators.qdrant-api-key = {
  files.api-key.neededFor = "qdrant";                    # u -> "<u>.service", user/group names allowed
  runtimeInputs = [ pkgs.openssl ];
  script = ''openssl rand -hex 32 > "$out"/api-key'';
};
# consumers read the store path:
#   EnvironmentFile = config.clan.core.vars.generators.qdrant-api-key.files.api-key.path;
```

### 6.3 Migration bridge (mandatory, keeps step 6 reversible)

For every mapped file: the old `*-secrets` unit stays in place, but its "write if absent"
branch is inverted — it now only *records* that it ran (`/var/lib/<svc>/.migrated-to-clan`) and
never rewrites the file. The service then reads the vars path. If a service misbehaves, revert
one line to the old path and the old file is still there. Delete the units in a separate commit
after a week of clean boots.

### 6.4 Status (done)

All of the above is implemented:

- `modules/clan/secrets.nix` declares the generators: 17 on `homelab` (18 files), 1 each on
  `raspberry-pi` (`restic-htpasswd`, 2 files) and `nixos` (`restic-client`, 1 file). Bifrost and
  Booklore split per credential so one rotation cannot orphan the other; `grok-oauth` keeps
  three keys in one file because two of them are the same value by construction.
- Every generator is **adopt-only**: `script` prints the adoption command and exits 1 instead
  of minting. Rationale and the full breakage table are in `docs/homelab.md` §"Secrets".
- Consumers in `modules/services/*.nix` and `modules/monitoring/backups.nix` read
  `config.clan.core.vars.generators.<gen>.files.<file>.path` and depend on
  Clan's `setupSecrets` activation script (no `age-decrypt-secrets.service` exists —
  that unit is only created when `systemd.sysusers.enable` is on); host files import `nixos.homelabVars`,
  `nixos.resticServerVars` or `nixos.resticClientVars` next to the consumers.
- `scripts/clan-adopt-secrets.sh` performs the adoption (normalising, idempotent, `--list` as
  the source of truth). Adopted so far: 15 of the 18 homelab files (every container/host secret
  readable without sudo), both pi `restic-htpasswd` files, and `homepage-vars` via its
  persisted prompt.
- Deliberate exceptions, both documented in the service module: `restic-htpasswd` is copied out
  of `/run/secrets` because `services.restic.server` uses `PrivateUsers=true` (root-owned files
  appear as `nobody` in that user namespace), and Homepage's env file stays at 0644 because the
  service is a `DynamicUser` with no stable uid.
- Equivalence gate: the §7 baseline `drvPath`s necessarily moved (consumers now read vars), so
  the gate was re-established on the new paths and all four hosts evaluate clean.
- Two bugs the script's own first run caught, both worth remembering: `qdrant-api-key` must be
  `QDRANT_API_KEY=` (the container's env is `QDRANT__SERVICE__API_KEY=`), and an `ssh -t` pty
  injects CR — a `\r` inside a bcrypt hash fails restic auth with no error at all. Both are
  fixed in the normaliser, not worked around at the call sites.
- Remaining before this step closes (all need a password prompt, so run them yourself from a
  terminal):
  - `./scripts/clan-adopt-secrets.sh homelab` → `grok-oauth`, `searx-secret`, `restic-client`
  - `./scripts/clan-adopt-secrets.sh nixos` → this workstation's `restic-client`
  - `clan vars upload homelab` and `clan vars upload raspberry-pi` — the store is external, so
    the ciphertext is NOT in the closure and `deploy` will not carry it.

## 7. Extracting services out of `modules/hosts/nixos-homelab.nix` (3,458 lines)

One commit per service, in this order (safest → most entangled):

1. `netdata` (:2009) — native, loopback only, no state.
2. `gatus` (:2046) — SQLite at `/var/lib/gatus/data.db`.
3. `searxng` (:3088) — one secret → vars first, then extraction.
4. `homepage` (:2307) — includes `homelab-stats` helper + human-entered vars.
5. `grok-oauth-proxy` (:2197) — OAuth state under `/var/lib/grok-oauth-proxy`.
6. `caddy` (:2828) — depends on the `proxyHosts` map and the CA; extract the vhost map as an
   option (`services.homelabReverseProxy.proxyHosts`), keep `tls internal` behaviour verbatim.
7. `nutify` (:3342), `reactive-resume` (:3232), `openbot` (:3172).
8. Incus workloads, in dependency order: `qdrant` (:946) → `bifrost` (:1060) → `hermes` (:1315)
   → `booklore`/`booklore-db` (:1686) → `homelable` (:624) → `mcphub` (:759) → `haos` (:476).
   **Bind mounts and `/var/lib/incus/*` paths must not change** — those are live data.

Each extracted module: `options.services.<name>.enable` + `mkIf`, registered in
`flake.modules.nixos.<name>` so another machine (pi, a future host) can import it.

`modules/hosts/nixos-homelab.nix` ends as: hardware import, `hostname`, `hostPlatform`,
`stateVersion`, `users`, Tailscale, firewall, Incus host setup, and `imports = [ nixos.services… ]`.

## 8. Rollout (each step = one commit + one gate)

**Step 0 — baseline.** Record `drvPath` for every host:
```bash
for h in nixos mango homelab raspberry-pi; do
  nix eval --raw .#$h/config.system.build.toplevel.drvPath; done > /tmp/baseline.drv
nix eval --raw .#darwinConfigurations.macbook-air/config.system.build.toplevel.drvPath >> /tmp/baseline.drv
```
Gate: file written; `git status` clean-ish commit point.

**Step 1 — inputs + no-op Clan wiring.** Add `clan-core`/`deploy-rs` inputs, `modules/clan/`,
and register the five machines under **temporary probe names** (`homelab-clan`, …) so they do
not collide with the existing `flake.nixosConfigurations.<host>` definitions (two definitions
of the same attribute would conflict, not merge). No host file changes yet.
Gate: `nix flake check --no-build` passes; `nix eval .#nixosConfigurations.homelab-clan.config.system.build.toplevel.drvPath`
**equals** the baseline for `homelab`. Repeat for all four; darwin via `darwinConfigurations.macbook-air-clan`.

**Step 2 — flip ownership.** Delete the `nixosSystem`/`darwinSystem` wrappers from
`modules/hosts/*.nix`, promote each host body to `flake.modules.<class>.<host>`, apply §4.3
(`hostPlatform`, drop `system` specialArg, `zen.nix` fix), rename probe machines to real names.
Gate: baseline `drvPath`s identical again (this is the moment a latent `specialArgs` dependency
would surface; a diff here is a bug, not a choice).

**Step 3 — deploy-rs dry run.** Add `modules/clan/deploy.nix`.
Gate: `nix flake check`, then `deploy .#homelab --dry-activate` and `deploy .#raspberry-pi --dry-activate`
from the workstation (no activation side effects).

**Step 4 — first real remote switch (pi first).** `raspberry-pi` is the least critical.
Gate: `deploy .#raspberry-pi` succeeds; `ssh pi readlink -f /run/current-system` matches the
built store path (`/run/current-system` is a directory, so `head -1` on it fails with
`Is a directory`); then a **rollback drill** on pi only (an activation script with a
deliberately failing `exit 1` — a failing *unit* does not reliably fail activation, so it
does not exercise `autoRollback`), proving magic rollback restores the previous generation.
Then `deploy .#homelab`.

**Step 5 — backup/dependency order check.** `resticServer` lives on pi and homelab is a client
(`modules/monitoring/backups.nix`): deploy pi before homelab in any window that touches
`modules/monitoring/**`. Gate: restic client on homelab still reaches `192.168.0.105:8000`.

**Step 6 — Clan secrets.** Vars enabled, generators added per §6.2, bridge units per §6.3, one
service at a time. Gate: after each service, `systemctl status <unit>` + `journalctl -u <unit>`
clean on homelab; `clan vars list` shows the generator with a resolved path.

**Step 7 — service extraction.** §7 order. Gate per commit: `drvPath` diff must be empty or a
reviewed one-liner (module inlining changes nothing about the closure).

**Step 8 — docs + fleet ops.** README/`AGENTS.md`/`docs/homelab.md` updated; add
`clan machines update` to the command reference; record the deploy node list.

## 9. Command reference after migration

```bash
# servers
deploy .#homelab                    # build + copy + activate, magic rollback on
deploy .#homelab --dry-activate     # what would change
deploy .#raspberry-pi               # builds on the Pi itself (remoteBuild)
deploy .#homelab -s                 # skip the (automatic) flake checks
clan machines update homelab        # Clan's own path, same target
clan machines update raspberry-pi --build-host localhost

# desktops (unchanged)
nh os switch
sudo nixos-rebuild switch --flake .#nixos

# fleet
clan machines list
clan vars list && clan vars get <generator>/<file>
```

Note: if flake evaluation ever needs `--impure` (see the `factory-desktop` pin), pass it
through deploy-rs as `deploy .#homelab -- --impure`.

## 10. Risks and rollback

| Risk | Mitigation |
|---|---|
| `../nixpkgs is incompatible with clan` (`_class` requirement) | our pin is `nixos-unstable` 2026 → fine; assert with `nix flake check` in step 1 |
| Duplicate `nixosConfigurations.<host>` during migration | probe names in step 1; real names only after deletion (step 2) |
| `specialArgs.system` silently used somewhere | step 2 gate compares `drvPath`; grep already narrowed it to `zen.nix:51` |
| 3,458-line homelab file → bad extraction | one service per commit, `drvPath` equality gate, bind-mounts untouched |
| Secrets regression strands a running container | §6.3 bridge units; old `/var/lib` files never deleted until a clean week |
| Pi is the restic server | deploy pi first in any monitoring-affecting window |
| darwin vars/activation limits | macbook keeps `darwin-rebuild`; deploy node optional and magicRollback off |
| Clan churn upstream | `nix flake update clan-core` only in a dedicated commit, gated by `drvPath` equality |

Rollback of any step = `git revert` + `nh os switch` (desktops) or `deploy .#<host>`
(servers), plus `nixos-rebuild --rollback` on a host as the last resort. No step deletes data.

## 11. Files touched (summary)

| File | Change |
|---|---|
| `flake.nix` | `clan-core`, `deploy-rs` inputs with `follows` on our nixpkgs |
| `modules/default.nix` | `imports` += `./clan` |
| `modules/clan/default.nix` | new — imports the four clan modules, `clan.specialArgs.flakeModules` |
| `modules/clan/inventory.nix` | new — meta, `inventory.machines` (©§4.1) |
| `modules/clan/machines.nix` | new — host composition lists, `flake.clan.machines` |
| `modules/clan/vars.nix` | new — `vars.settings`, `clan.core.vars.generators.*` |
| `modules/clan/deploy.nix` | new — `flake.deploy.nodes`, `flake.checks` |
| `modules/hosts/*.nix` | drop `nixosSystem`/`darwinSystem` wrappers, register `flake.modules.<class>.<host>`, add `hostPlatform`, hoist home-manager wiring |
| `modules/desktop/zen.nix` | `system` arg → `pkgs.stdenv.hostPlatform.system` |
| `modules/services/*/` | new — one module per extracted homelab service |
| `modules/hosts/nixos-homelab.nix` | 3,458 → host identity + service imports |
| `modules/monitoring/backups.nix` | restic htpasswd/client env from vars |
| `README.md`, `docs/homelab.md`, `AGENTS.md` | new deploy workflow, `clan`/`deploy` commands, layout invariants |
| `.gitignore` | keep `*.env`; add `/.clan/` runtime state, `*.age` keys if any land in-tree |

## 12. Open items to confirm during execution (not blocking the plan)

- Admin username on `homelab` for `deploy.nodes.homelab.sshUser` (read it from
  `config.users.users` before writing the node).
- Exact LAN names: `homelab.home.arpa` / `pi.home.arpa` resolve today? Caddy already serves
  `*.home.arpa` hostnames and homelab binds `192.168.0.160`, so either is available; confirm
  DNS (AdGuard on pi) before hardcoding.
- Whether to adopt `clan.inventory.instances` services (`sshd`, `users`, `admin`) or keep the
  current hand-written `openssh`/`users` modules — recommendation: adopt `sshd` + `users` only
  after step 6 (they need vars), leave `admin` (root password) alone.
- Optional later: `clan machines install` (nixos-anywhere) for a future pi/desktop reinstall.
