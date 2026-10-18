#!/usr/bin/env python3
"""Audit and bump the application pins in this flake.

Nix needs a fixed-output hash at evaluation time, so "just take the latest" is
not possible for packaged desktop apps: the hash must be known before the build
starts. This script does the mechanical half of a bump -- find the newest
release, prefetch the hash, rewrite the module -- and leaves the decision to
you.

Usage:
  nix run .#update-pins                     # audit everything, rewrite nothing
  nix run .#update-pins -- --write          # apply bumps (hashes prefetched)
  nix run .#update-pins -- --write --build  # ...then build #nixos
  nix run .#update-pins -- --only orca,zcode
  nix run .#update-pins -- --write --flake  # also `nix flake update`

Exit status: 0 nothing to do, 1 bumps available (dry run), 2 hard failure.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import urllib.request
from dataclasses import dataclass, field

UA = "nixos-config-update-pins"


# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------


def find_root() -> str:
    override = os.environ.get("UPDATE_PINS_ROOT")
    if override:
        return os.path.abspath(override)
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            check=True,
        )
        return out.stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


ROOT = find_root()


class Fail(Exception):
    pass


# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------


def run(cmd: list[str], *, check: bool = True) -> str:
    proc = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    if check and proc.returncode != 0:
        detail = proc.stderr.strip() or proc.stdout.strip()
        raise Fail(f"`{' '.join(cmd)}` failed: {detail}")
    return proc.stdout


def http_get(url: str) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "*/*"})
    with urllib.request.urlopen(req, timeout=45) as resp:
        return resp.read().decode("utf-8", "replace")


def http_json(url: str):
    req = urllib.request.Request(
        url, headers={"User-Agent": UA, "Accept": "application/vnd.github+json"}
    )
    with urllib.request.urlopen(req, timeout=45) as resp:
        return json.load(resp)


def url_status(url: str) -> str:
    proc = subprocess.run(
        ["curl", "-s", "-o", "/dev/null", "-I", "-L", "-w", "%{http_code}", "--max-time", "20", url],
        capture_output=True,
        text=True,
    )
    return proc.stdout.strip()


def version_key(text: str) -> tuple[int, ...]:
    """Ordering key for versions like 1.2.3, v1.2.3, 0.1.1-preview.20261017."""
    base = text.lstrip("v")
    head, _, pre = base.partition("-")
    numbers = [int(x) for x in re.findall(r"\d+", head)][:4]
    numbers += [0] * (4 - len(numbers))
    # A pre-release sorts below the matching final release.
    return tuple(numbers) + (1 if pre else 0,)


def prefetch_file(url: str) -> str:
    """SRI hash of a file, for fetchurl / requireFile."""
    out = json.loads(
        run(["nix", "store", "prefetch-file", "--hash-type", "sha256", "--json", url])
    )
    return out["hash"]


def prefetch_unpack(url: str) -> str:
    """SRI hash of an unpacked archive tree, for fetchFromGitHub/fetchzip."""
    out = json.loads(
        run(
            [
                "nix",
                "store",
                "prefetch-file",
                "--unpack",
                "--hash-type",
                "sha256",
                "--json",
                url,
            ]
        )
    )
    return out["hash"]


def to_nix32(sri: str) -> str:
    return run(["nix", "hash", "convert", "--hash-algo", "sha256", "--to", "nix32", sri]).strip()


# ---------------------------------------------------------------------------
# Pin model
# ---------------------------------------------------------------------------


@dataclass
class Pin:
    """One pinned application.

    anchor          text identifying the block; all substitutions happen after it
    version_re      regex whose `v` group is the current version
    version_tpl     replacement template for the version literal, `{v}` substituted
    lookup          how to find the newest version (see resolve())
    url_re/url_tpl  the URL literal, when the module spells one out
    hash_re/hash_*  the hash literal and how to compute it
    """

    name: str
    file: str
    anchor: str
    version_re: str
    version_tpl: str
    lookup: dict
    url_re: str | None = None
    url_tpl: str | None = None
    hash_re: str | None = None
    hash_kind: str | None = None  # file | nix32 | unpack | None
    hash_url: str | None = None  # overrides url_tpl for the prefetch
    extra: list[tuple[str, str]] = field(default_factory=list)
    note: str = ""


DEVELOP = "modules/packages/dev.nix"
SYSTEM = "modules/packages/system.nix"

PINS: list[Pin] = [
    Pin(
        name="orca",
        file=DEVELOP,
        anchor='pname = "orca-ide";',
        version_re=r'version = "(?P<v>[0-9][0-9.]*)";',
        version_tpl='version = "{v}";',
        lookup={"kind": "github", "repo": "stablyai/orca"},
        url_re=r"https://github\.com/stablyai/orca/releases/download/v[0-9.]+/orca-linux\.AppImage",
        url_tpl="https://github.com/stablyai/orca/releases/download/v{v}/orca-linux.AppImage",
        hash_re=r'hash = "sha256-[^"]+";',
        hash_kind="file",
    ),
    Pin(
        name="oh-my-pi",
        file=DEVELOP,
        anchor='pname = "oh-my-pi";',
        version_re=r'version = "(?P<v>[0-9][0-9.]*)";',
        version_tpl='version = "{v}";',
        lookup={"kind": "github", "repo": "can1357/oh-my-pi"},
        url_re=r"https://github\.com/can1357/oh-my-pi/releases/download/v[0-9.]+/omp-linux-x64",
        url_tpl="https://github.com/can1357/oh-my-pi/releases/download/v{v}/omp-linux-x64",
        hash_re=r'hash = "sha256-[^"]+";',
        hash_kind="file",
    ),
    Pin(
        name="emdash",
        file=DEVELOP,
        anchor='pname = "emdash";',
        version_re=r'version = "(?P<v>[0-9][0-9.]*)";',
        version_tpl='version = "{v}";',
        lookup={"kind": "github", "repo": "generalaction/emdash"},
        url_re=r"https://github\.com/generalaction/emdash/releases/download/v[0-9.]+/emdash-x86_64\.AppImage",
        url_tpl="https://github.com/generalaction/emdash/releases/download/v{v}/emdash-x86_64.AppImage",
        hash_re=r'hash = "sha256-[^"]+";',
        hash_kind="file",
    ),
    Pin(
        name="eigent",
        file=DEVELOP,
        anchor="eigentVersion = ",
        version_re=r'eigentVersion = "(?P<v>[0-9][0-9.]*)";',
        version_tpl='eigentVersion = "{v}";',
        lookup={"kind": "github", "repo": "eigent-ai/eigent"},
        url_re=r'url = "https://github\.com/eigent-ai/eigent/releases/download/v[0-9.]+/Eigent-[0-9.]+\.AppImage";',
        url_tpl='url = "https://github.com/eigent-ai/eigent/releases/download/v{v}/Eigent-{v}.AppImage";',
        hash_re=r'hash = "sha256-[^"]+";',
        hash_kind="file",
        extra=[(r'name = "Eigent-[0-9.]+\.AppImage";', 'name = "Eigent-{v}.AppImage";')],
    ),
    Pin(
        name="openresearch",
        file=DEVELOP,
        anchor="openresearchVersion = ",
        version_re=r'openresearchVersion = "(?P<v>[0-9][0-9.]*)";',
        version_tpl='openresearchVersion = "{v}";',
        lookup={"kind": "github", "repo": "alphaXiv/OpenResearch"},
        url_re=r'url = "https://github\.com/alphaXiv/OpenResearch/releases/download/v[0-9.]+/OpenResearch-x86_64\.AppImage";',
        url_tpl='url = "https://github.com/alphaXiv/OpenResearch/releases/download/v{v}/OpenResearch-x86_64.AppImage";',
        hash_re=r'hash = "sha256-[^"]+";',
        hash_kind="file",
    ),
    Pin(
        name="unsloth",
        file=SYSTEM,
        anchor='pname = "unsloth-desktop";',
        version_re=r'version = "(?P<v>[0-9][^"]*)";',
        version_tpl='version = "{v}";',
        lookup={"kind": "github", "repo": "unslothai/unsloth"},
        url_re=r'url = "https://github\.com/unslothai/unsloth/releases/download/v[^/]+/Unsloth-Desktop-Linux\.AppImage";',
        url_tpl='url = "https://github.com/unslothai/unsloth/releases/download/v{v}/Unsloth-Desktop-Linux.AppImage";',
        hash_re=r'hash = "sha256-[^"]+";',
        hash_kind="file",
    ),
    Pin(
        name="koboldcpp",
        file=SYSTEM,
        anchor='name = "koboldcpp";',
        version_re=r'version="(?P<v>[0-9][0-9.]*)"',
        version_tpl='version="{v}"',
        lookup={"kind": "github", "repo": "LostRuins/koboldcpp"},
        note="no hash: the launcher fetches the binary on first run",
    ),
    Pin(
        name="capy",
        file="modules/packages/capy.nix",
        anchor="capyVersion = ",
        version_re=r'capyVersion = "(?P<v>[0-9][0-9.]*)";',
        version_tpl='capyVersion = "{v}";',
        lookup={"kind": "manual", "note": "downloads.capy.ai exposes no version index"},
        url_re=r'url = "https://downloads\.capy\.ai/stable/capy-[0-9.]+-x64\.tar\.gz";',
        url_tpl='url = "https://downloads.capy.ai/stable/capy-{v}-x64.tar.gz";',
        hash_re=r'hash = "sha256-[^"]+";',
        hash_kind="file",
    ),
    Pin(
        name="mango",
        file="modules/mangowm/wm.nix",
        anchor="mangoPinned = pkgs:",
        version_re=r'version = "(?P<v>[0-9][0-9.]*)";',
        version_tpl='version = "{v}";',
        lookup={"kind": "github", "repo": "mangowm/mango"},
        hash_re=r'hash = "sha256-[^"]+";',
        hash_kind="unpack",
        hash_url="https://github.com/mangowm/mango/archive/{rev}.tar.gz",
        extra=[(r'rev = "[0-9a-f]{40}";', 'rev = "{rev}";')],
        note="also rewrites the pinned commit rev",
    ),
    Pin(
        name="grok-bot",
        file=DEVELOP,
        anchor="grokBotVersion = ",
        version_re=r'grokBotVersion = "(?P<v>[0-9][0-9.]*)";',
        version_tpl='grokBotVersion = "{v}";',
        lookup={"kind": "grok-bot"},
        hash_re=r'sha256 = "[0-9a-z]+";',
        hash_kind="nix32",
    ),
    Pin(
        name="zcode",
        file=DEVELOP,
        anchor="zcodeVersion = ",
        version_re=r'zcodeVersion = "(?P<v>[0-9][0-9.]*)";',
        version_tpl='zcodeVersion = "{v}";',
        lookup={"kind": "zcode"},
        hash_re=r'hash = "sha256-[^"]+";',
        hash_kind="file",
        hash_url="https://cdn-zcode.z.ai/zcode/electron/releases/{v}/linux-x64/ZCode-{v}-linux-x64.AppImage",
    ),
    Pin(
        name="autoclaw",
        file=DEVELOP,
        anchor="autoclawVersion = ",
        version_re=r'autoclawVersion = "(?P<v>[0-9][0-9.]*)";',
        version_tpl='autoclawVersion = "{v}";',
        lookup={
            "kind": "manual",
            "note": "Linux build is published only through the site download button",
        },
    ),
    Pin(
        name="t3code",
        file=DEVELOP,
        anchor="t3code = pkgs.t3code.override {",
        version_re=r'version = "(?P<v>[0-9][0-9.]*)";',
        version_tpl='version = "{v}";',
        lookup={"kind": "t3code"},
        hash_re=r'hash = "sha256-[^"]+";',
        hash_kind="unpack",
        hash_url="https://github.com/pingdotgg/t3code/archive/refs/tags/v{v}.tar.gz",
        note="pnpmDeps hash must be refreshed separately (see --write output)",
    ),
]

# Reported every run, never bumped: these need a human decision.
FROZEN = {
    "zoom-vdi": "pinned for Citrix/VDI compatibility (AGENTS.md)",
    "epic-launcher": "requireFile manual download; no stable upstream URL",
    "flakes-inputs": "opencode/hyprland/etc. move with `nix flake update --flake`, not here",
}

# A pin that jumps more than this many minor versions is worth eyeballing.
MAX_MINOR_JUMP = 3


# ---------------------------------------------------------------------------
# Latest-version resolution
# ---------------------------------------------------------------------------


def resolve(pin: Pin) -> tuple[str | None, str]:
    """Return (latest_version, note). Version None means "cannot automate"."""
    kind = pin.lookup["kind"]

    if kind == "github":
        data = http_json(f"https://api.github.com/repos/{pin.lookup['repo']}/releases/latest")
        tag = data.get("tag_name")
        if not tag:
            return None, "repository has no releases"
        return tag.lstrip("v"), ""

    if kind == "grok-bot":
        html = http_get("https://cursor.com/download/bot?download=1")
        m = re.search(
            r"https://downloads\.cursor\.com/grokbot/stable/[0-9a-f]+"
            r"/linux/x64/grok-bot_(?P<v>[0-9.]+)_amd64\.deb",
            html,
        )
        if not m:
            return None, "no linux/x64 .deb link on the download page"
        return m.group("v"), ""

    if kind == "zcode":
        # The CDN exposes no version index, so read the changelog and confirm
        # each candidate actually has a downloadable Linux artifact.
        html = http_get("https://zcode.z.ai/en/changelog")
        versions = {m.group(0) for m in re.finditer(r"\b\d+\.\d+\.\d+\b", html)}
        for candidate in sorted(versions, key=version_key, reverse=True):
            url = (
                "https://cdn-zcode.z.ai/zcode/electron/releases/"
                f"{candidate}/linux-x64/ZCode-{candidate}-linux-x64.AppImage"
            )
            if url_status(url) == "200":
                return candidate, ""
        return None, "no reachable Linux artifact in the changelog"

    if kind == "t3code":
        data = http_json("https://api.github.com/repos/pingdotgg/t3code/releases/latest")
        tag = data.get("tag_name")
        if not tag:
            return None, "repository has no releases"
        try:
            nixpkgs_version = run(
                [
                    "nix",
                    "eval",
                    "--impure",
                    "--raw",
                    "--expr",
                    f'(builtins.getFlake "{ROOT}").inputs.nixpkgs'
                    ".legacyPackages.x86_64-linux.t3code.version",
                ]
            ).strip()
        except Fail:
            nixpkgs_version = "?"
        return tag.lstrip("v"), f"nixpkgs currently ships {nixpkgs_version}"

    return None, pin.lookup.get("note", "no automated lookup")


def tag_commit(repo: str, tag: str) -> str:
    ref = http_json(f"https://api.github.com/repos/{repo}/git/ref/tags/{tag}")
    obj = ref["object"]
    if obj["type"] == "tag":  # annotated tag: peel to the commit
        obj = http_json(obj["url"])["object"]
    return obj["sha"]


def grok_bot_deb_url(version: str) -> str:
    """The .deb URL embeds a build hash; recover it from the download page."""
    html = http_get("https://cursor.com/download/bot?download=1")
    m = re.search(
        r"https://downloads\.cursor\.com/grokbot/stable/[0-9a-f]+"
        rf"/linux/x64/grok-bot_{re.escape(version)}_amd64\.deb",
        html,
    )
    if not m:
        raise Fail(f"no linux/x64 .deb URL for grok-bot {version}")
    return m.group(0)


# ---------------------------------------------------------------------------
# Rewriting
# ---------------------------------------------------------------------------


def read(path: str) -> str:
    with open(os.path.join(ROOT, path), encoding="utf-8") as fh:
        return fh.read()


def write(path: str, text: str) -> None:
    with open(os.path.join(ROOT, path), "w", encoding="utf-8") as fh:
        fh.write(text)


def replace_after(text: str, anchor: str, pattern: str, replacement: str, what: str) -> str:
    """Replace the first match of `pattern` that occurs at or after `anchor`."""
    idx = text.find(anchor)
    if idx == -1:
        raise Fail(f"{what}: anchor not found ({anchor!r})")
    head, tail = text[:idx], text[idx:]
    new_tail, count = re.subn(pattern, replacement, tail, count=1)
    if count != 1:
        raise Fail(f"{what}: no match for {pattern!r} after the anchor")
    return head + new_tail


def apply_bump(pin: Pin, old: str, new: str) -> list[str]:
    """Rewrite one pin in place. Returns the list of changes made."""
    text = read(pin.file)
    changed = [f"{old} -> {new}"]

    text = replace_after(text, pin.anchor, pin.version_re, pin.version_tpl.format(v=new), pin.name)

    # A pinned commit rev needs to track the tag, not just the version string.
    if pin.name == "mango":
        rev = tag_commit("mangowm/mango", f"v{new}")
        text = replace_after(
            text, pin.version_tpl.format(v=new), r'rev = "[0-9a-f]{40}";', f'rev = "{rev}";', pin.name
        )
        changed.append(f"rev {rev[:12]}")
        sri = prefetch_unpack(pin.hash_url.format(v=new, rev=rev))
        text = replace_after(
            text, f'rev = "{rev}";', pin.hash_re, f'hash = "{sri}";', pin.name
        )
        changed.append("hash")
        write(pin.file, text)
        return changed

    for pattern, template in pin.extra:
        text = replace_after(text, pin.anchor, pattern, template.format(v=new), pin.name)

    if pin.url_re and pin.url_tpl:
        text = replace_after(text, pin.anchor, pin.url_re, pin.url_tpl.format(v=new), pin.name)
        changed.append("url")

    if pin.hash_kind:
        url = (pin.hash_url or pin.url_tpl or "").format(v=new)
        if pin.name == "grok-bot":
            url = grok_bot_deb_url(new)
        if not url:
            raise Fail(f"{pin.name}: hash configured but no URL to prefetch")

        if pin.hash_kind == "unpack":
            value = prefetch_unpack(url)
        else:
            sri = prefetch_file(url)
            value = to_nix32(sri) if pin.hash_kind == "nix32" else sri

        label = "sha256" if pin.hash_kind == "nix32" else "hash"
        text = replace_after(
            text, pin.anchor, pin.hash_re, f'{label} = "{value}";', pin.name
        )
        changed.append("hash")

    write(pin.file, text)
    return changed


# ---------------------------------------------------------------------------
# Flake inputs
# ---------------------------------------------------------------------------


def update_flake() -> list[str]:
    before = json.loads(run(["nix", "flake", "metadata", "--json"]))["locks"]["nodes"]
    run(["nix", "flake", "update"])
    after = json.loads(run(["nix", "flake", "metadata", "--json"]))["locks"]["nodes"]

    moved = []
    for name in sorted(set(before) & set(after)):
        if name == "root":
            continue
        old = (before[name].get("locked") or {}).get("rev", "")
        new = (after[name].get("locked") or {}).get("rev", "")
        if old and new and old != new:
            moved.append((name, old[:12], new[:12]))
    return moved


# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------


def section(title: str, rows: list[tuple[str, str]], width: int) -> None:
    if not rows:
        return
    print(f"\n{title}")
    for name, detail in rows:
        print(f"  {name:<{width}}  {detail}")


def main() -> int:
    ap = argparse.ArgumentParser(description="Audit and bump application pins.")
    ap.add_argument("--write", action="store_true", help="apply bumps (default: audit only)")
    ap.add_argument("--build", action="store_true", help="build #nixos after writing")
    ap.add_argument("--flake", action="store_true", help="also run `nix flake update`")
    ap.add_argument("--only", default="", help="comma-separated pin names")
    args = ap.parse_args()

    only = {n.strip() for n in args.only.split(",") if n.strip()}
    selected = [p for p in PINS if not only or p.name in only]
    if only and not selected:
        print(f"no such pin(s): {', '.join(sorted(only))}", file=sys.stderr)
        print(f"available: {', '.join(p.name for p in PINS)}", file=sys.stderr)
        return 2

    bumps: list[tuple[str, str]] = []
    current: list[tuple[str, str]] = []
    manual: list[tuple[str, str]] = []
    skipped: list[tuple[str, str]] = []
    failures: list[tuple[str, str]] = []
    followups: list[str] = []

    for pin in selected:
        try:
            body = read(pin.file)
            start = body.find(pin.anchor)
            if start == -1:
                raise Fail(f"anchor not found ({pin.anchor!r})")
            m = re.search(pin.version_re, body[start:])
            if not m:
                raise Fail("version literal not found after the anchor")
            old = m.group("v")

            new, note = resolve(pin)
            if not new:
                manual.append((pin.name, note or "no automated lookup"))
                continue

            if version_key(new) <= version_key(old):
                current.append((pin.name, old))
                continue

            old_key, new_key = version_key(old), version_key(new)
            if old_key[0] != new_key[0]:
                skipped.append(
                    (pin.name, f"{old} -> {new} crosses a major version; bump by hand")
                )
                continue
            if new_key[1] - old_key[1] > MAX_MINOR_JUMP:
                skipped.append(
                    (pin.name, f"{old} -> {new} jumps {new_key[1] - old_key[1]} minor versions")
                )
                continue

            if args.write:
                changes = apply_bump(pin, old, new)
                bumps.append((pin.name, "  ".join(changes)))
                if pin.name == "t3code":
                    followups.append(
                        "t3code: the fetchPnpmDeps hash changed with the source. "
                        "Set it from the upstream bump PR (NixOS/nixpkgs#575132) or "
                        "run the build once and copy the reported outputHash."
                    )
            else:
                suffix = f"  [{note}]" if note else ""
                bumps.append((pin.name, f"{old} -> {new}{suffix}"))
        except Fail as exc:
            failures.append((pin.name, str(exc)))
        except Exception as exc:  # network/shape surprises must not abort the audit
            failures.append((pin.name, f"{type(exc).__name__}: {exc}"))

    width = max(
        [len(p.name) for p in PINS] + [len(n) for n in FROZEN] + [len("flake inputs")]
    )
    section("BUMPS" + ("" if args.write else " (dry run; --write applies)"), bumps, width)
    section("UP TO DATE", current, width)
    section("MANUAL (no automated lookup)", manual, width)
    section("SKIPPED (needs a human decision)", skipped, width)
    section("FAILED", failures, width)
    section("FROZEN (never bumped automatically)", list(FROZEN.items()), width)

    if args.flake:
        print("\nFLAKE INPUTS")
        try:
            moved = update_flake()
            if moved:
                for name, old, new in moved:
                    print(f"  {name:<{width}}  {old} -> {new}")
                print("  note: a nixpkgs move means a full-system rebuild")
            else:
                print("  (nothing moved)")
        except Fail as exc:
            print(f"  failed: {exc}")
            failures.append(("flake inputs", str(exc)))

    if args.write and bumps:
        print("\nSYNTAX CHECK")
        for path in sorted({p.file for p in selected}):
            proc = subprocess.run(
                ["nix-instantiate", "--parse", os.path.join(ROOT, path)],
                capture_output=True,
                text=True,
            )
            if proc.returncode == 0:
                print(f"  {path}: ok")
            else:
                print(f"  {path}: FAILED")
                print(f"    {proc.stderr.strip().splitlines()[0] if proc.stderr.strip() else ''}")
                failures.append((path, "parse error"))

    for note in followups:
        print(f"\nNEXT STEP\n  {note}")

    if args.build and bumps and not failures:
        print("\nBUILDING #nixos (this takes a while)...")
        proc = subprocess.run(
            [
                "nix",
                "build",
                "--no-link",
                "--print-out-paths",
                ".#nixosConfigurations.nixos.config.system.build.toplevel",
            ],
            cwd=ROOT,
        )
        if proc.returncode == 0:
            print("build OK")
        else:
            print("build FAILED")
            failures.append(("build", "#nixos toplevel"))

    print()
    if failures:
        print(f"{len(failures)} problem(s); see FAILED above.")
        return 2
    if bumps and not args.write:
        print(f"{len(bumps)} bump(s) available. Re-run with --write to apply.")
        return 1
    if bumps:
        print(f"Applied {len(bumps)} bump(s). Review with `git diff`, then rebuild.")
    else:
        print("Everything is current.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
