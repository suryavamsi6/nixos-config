#!/usr/bin/env python3
"""Import dual-boot Windows Bluetooth pairing keys into BlueZ.

A paired device keeps one key per host address: a classic (BR/EDR) device stores
a single link key, an LE device an LTK/IRK, and both operating systems on a
dual-boot machine present the *same* Bluetooth adapter address.  Whichever OS
paired the device last therefore owns the key the device will accept, and the
other OS is asked to pair again.  This tool copies the Windows side of that
pairing into BlueZ so both installations hold identical material.  Pair or
re-pair on Windows last, then reboot (or run this command).

Where the keys live on Windows (hive ``C:\\Windows\\System32\\config\\SYSTEM``)::

  ControlSet00N\\Services\\BTHPORT\\Parameters\\Keys\\<adapter-address>
      <device-address>              REG_BINARY  classic 16-byte link key
      <device-address>\\LTK         REG_BINARY  Bluetooth 5.1 LE long term key
      <device-address>\\IRK         REG_BINARY  LE identity resolving key
      <device-address>\\CSRK        REG_BINARY  LE local signature key
      <device-address>\\ERand       REG_QWORD   LE random number
      <device-address>\\EDIV        REG_DWORD   LE encrypted diversifier
      <device-address>\\KeyLength   REG_DWORD   LTK size in bytes
      <device-address>\\AddressType REG_DWORD   0 = public, 1 = random

Windows ACLs that key to the SYSTEM account, but ACLs do not exist on an
offline copy, so the hive can be read from Linux without booting Windows.
chntpw's ``reged`` exports it as text; the hive is copied to a temporary
directory first so reged can replay its transaction logs without ever writing
to the Windows volume.

Only the fields this tool knows about are changed: existing BlueZ ``info``
files keep every other line, and a copy of each file it rewrites is stored
under ``/var/lib/dualboot-bluetooth/backups``.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

DEFAULT_WINDOWS_ROOT = "/mnt/windows"
DEFAULT_BLUETOOTH_DIR = "/var/lib/bluetooth"
DEFAULT_BACKUP_DIR = "/var/lib/dualboot-bluetooth/backups"

HIVE_CANDIDATES = (
    "Windows/System32/config/SYSTEM",
    "windows/system32/config/system",
)
BTHPORT_RELATIVE = r"Services\BTHPORT\Parameters"
CONTROL_SET_PREFIX = "ControlSet"

# Sections BlueZ uses for an LE long term key, depending on the role this host
# played when the bond was created.  Every section that already exists is
# updated; a fresh file gets both of the current spellings.
LE_KEY_SECTIONS = ("LongTermKey", "PeripheralLongTermKey", "SlaveLongTermKey")

COMPACT_MAC_RE = re.compile(r"^[0-9a-fA-F]{12}$")


def compact_mac(text: str) -> str | None:
    """``C8:A3:E8:F0:EE:5C`` / ``c8a3e8f0ee5c`` -> uppercase 12 hex digits."""
    cleaned = re.sub(r"[^0-9a-fA-F]", "", text or "")
    if not COMPACT_MAC_RE.match(cleaned):
        return None
    return cleaned.upper()


def pretty_mac(compact: str) -> str:
    return ":".join(compact[i : i + 2] for i in range(0, 12, 2))


def reverse_mac(compact: str) -> str:
    """Byte-reverse an address.

    Windows stores a Bluetooth address with reversed octets in a few places;
    the caller only trusts a reversed reading when it names an address BlueZ
    already knows.
    """
    return "".join(reversed([compact[i : i + 2] for i in range(0, 12, 2)]))


# --------------------------------------------------------------------------
# .reg text parsing (chntpw `reged -x` output is regedit 4/5 text format)
# --------------------------------------------------------------------------


class RegFile:
    """Values of a textual ``.reg`` export, keyed by their full path."""

    def __init__(self, text: str):
        self.sections: "dict[str, dict[str, str]]" = {}
        self._parse(text)

    def _parse(self, text: str) -> None:
        lines = text.splitlines()
        section: str | None = None
        i = 0
        while i < len(lines):
            line = lines[i].rstrip("\r")
            # Continuation lines end with a single backslash.
            while line.endswith("\\") and i + 1 < len(lines):
                i += 1
                line = line[:-1] + lines[i].rstrip("\r")
            i += 1

            stripped = line.strip()
            if not stripped or stripped.startswith(";") or stripped.startswith("#"):
                continue
            if stripped.startswith("Windows Registry Editor"):
                continue
            if stripped.startswith("[") and stripped.endswith("]"):
                section = stripped[1:-1].strip()
                self.sections.setdefault(section, {})
                continue
            if section is None or "=" not in line:
                continue

            name, _, value = line.partition("=")
            name = name.strip()
            if name == "@":
                name = ""
            elif name.startswith('"') and name.endswith('"'):
                name = name[1:-1].replace('""', '"')
            self.sections[section][name] = value.strip()

    def relative(self, prefix: str) -> "dict[str, dict[str, str]]":
        """Sections below ``prefix``, keyed by their path relative to it.

        ``reged -x`` prints full paths rooted at the hive, so the prefix is
        matched at a path-component boundary rather than only at the start.
        """
        wanted = prefix.lower().strip("\\")
        found: "dict[str, dict[str, str]]" = {}
        marker = "\\" + wanted + "\\"
        for path, values in self.sections.items():
            normalised = path.lower().strip("\\")
            if normalised == wanted or normalised.endswith("\\" + wanted):
                found[""] = values
            elif normalised.startswith(wanted + "\\"):
                found[normalised[len(wanted) + 1 :]] = values
            else:
                position = normalised.find(marker)
                if position >= 0:
                    found[normalised[position + len(marker) :]] = values
        return found


def value_bytes(value: str) -> bytes | None:
    """Decode ``hex:`` / ``hex(N):`` value data."""
    match = re.match(r"^hex(?:\((\d+|[bB])\))?:(.*)$", value.strip(), re.IGNORECASE | re.DOTALL)
    if not match:
        return None
    body = match.group(2).replace(",", " ").replace("\\", " ")
    try:
        return bytes(int(part, 16) for part in body.split())
    except ValueError:
        return None


def value_text(value: str) -> str | None:
    stripped = value.strip()
    if stripped.startswith('"') and stripped.endswith('"') and len(stripped) >= 2:
        return stripped[1:-1]
    # A REG_SZ / REG_EXPAND_SZ exported as raw bytes is UTF-16LE text.
    if re.match(r"^hex\([12]\):", stripped, re.IGNORECASE):
        raw = value_bytes(stripped)
        if raw:
            try:
                return raw.decode("utf-16-le").rstrip("\x00")
            except UnicodeDecodeError:
                return None
    return None


def value_int(value: str) -> int | None:
    stripped = value.strip()
    if stripped.lower().startswith("dword:"):
        body = stripped[6:].replace(" ", "")
        try:
            return int(body, 16)
        except ValueError:
            pass
        raw = value_bytes("hex:" + stripped[6:].replace(" ", ","))
        return int.from_bytes(raw, "little") if raw else None
    if stripped.lower().startswith("hex(b):"):
        raw = value_bytes(stripped)
        # REG_QWORD is stored little-endian.
        return int.from_bytes(raw, "little") if raw else None
    data = value_bytes(stripped)
    if data is not None and len(data) <= 8:
        return int.from_bytes(data, "little")
    return None


# --------------------------------------------------------------------------
# BlueZ `info` files
# --------------------------------------------------------------------------


class InfoFile:
    """BlueZ ``info`` document that round-trips unknown lines unchanged."""

    def __init__(self, text: str = ""):
        self.entries: "list[list[str]]" = []
        if text.strip():
            self._parse(text)

    def _parse(self, text: str) -> None:
        section = ""
        for raw in text.splitlines():
            line = raw.rstrip("\r")
            stripped = line.strip()
            if stripped.startswith("[") and stripped.endswith("]"):
                section = stripped[1:-1].strip()
                self.entries.append(["section", section])
            elif stripped and "=" in line and not stripped.startswith("#"):
                key, _, value = line.partition("=")
                self.entries.append(["value", section, key.strip(), value.strip()])
            else:
                self.entries.append(["raw", line])

    def has_section(self, name: str) -> bool:
        wanted = name.lower()
        return any(e[0] == "section" and e[1].lower() == wanted for e in self.entries)

    def get(self, section: str, key: str) -> str | None:
        target = section.lower()
        wanted = key.lower()
        for entry in self.entries:
            if entry[0] == "value" and entry[1].lower() == target and entry[2].lower() == wanted:
                return entry[3]
        return None

    def set(self, section: str, key: str, value: str) -> bool:
        """Set ``key`` in ``section``; returns True when the file changed."""
        target = section.lower()
        wanted = key.lower()
        for entry in self.entries:
            if entry[0] == "value" and entry[1].lower() == target and entry[2].lower() == wanted:
                if entry[3] == value:
                    return False
                entry[3] = value
                return True

        start = next(
            (i for i, e in enumerate(self.entries) if e[0] == "section" and e[1].lower() == target),
            None,
        )
        if start is None:
            if self.entries and self.entries[-1][0] != "raw":
                self.entries.append(["raw", ""])
            self.entries.append(["section", section])
            self.entries.append(["value", section, key, value])
            return True

        end = len(self.entries)
        for i in range(start + 1, len(self.entries)):
            if self.entries[i][0] == "section":
                end = i
                break
        # Keep the blank line that separates two sections where it belongs.
        while end - 1 > start and self.entries[end - 1][0] == "raw" and not self.entries[end - 1][1].strip():
            end -= 1
        self.entries.insert(end, ["value", section, key, value])
        return True

    def render(self) -> str:
        out: "list[str]" = []
        for entry in self.entries:
            if entry[0] == "value":
                out.append(f"{entry[2]}={entry[3]}")
            elif entry[0] == "section":
                if out and out[-1].strip():
                    out.append("")
                out.append(f"[{entry[1]}]")
            else:
                out.append(entry[1])
        return "\n".join(out).rstrip("\n") + "\n"


# --------------------------------------------------------------------------
# Bond model
# --------------------------------------------------------------------------


class Bond:
    def __init__(self, mac: str):
        self.mac = mac
        self.link_key: bytes | None = None
        self.ltk: bytes | None = None
        self.irk: bytes | None = None
        self.csrk: bytes | None = None
        self.rand: int | None = None
        self.ediv: int | None = None
        self.enc_size: int | None = None
        self.address_type: str | None = None
        self.name: str | None = None

    @property
    def is_le(self) -> bool:
        return self.ltk is not None or self.irk is not None

    def apply(self, info: InfoFile, create: bool) -> "list[str]":
        changed: "list[str]" = []

        if create:
            technologies = []
            if self.link_key:
                technologies.append("BR/EDR")
            if self.is_le:
                technologies.append("LE")
            if info.set("General", "Name", self.name or self.mac):
                changed.append("General.Name")
            if info.set("General", "AddressType", self.address_type or "public"):
                changed.append("General.AddressType")
            if info.set("General", "SupportedTechnologies", ";".join(technologies) + ";"):
                changed.append("General.SupportedTechnologies")
            info.set("General", "Trusted", "true")
            info.set("General", "Blocked", "false")

        if self.link_key:
            if info.set("LinkKey", "Key", self.link_key.hex().upper()):
                changed.append("LinkKey.Key")
            # Windows does not record the kernel link key type.  Preserve what
            # BlueZ wrote; only a brand new section needs a default (4 is the
            # unauthenticated combination key BlueZ reports for SSP pairings).
            if info.get("LinkKey", "Type") is None and info.set("LinkKey", "Type", "4"):
                changed.append("LinkKey.Type")
            if info.get("LinkKey", "PINLength") is None and info.set("LinkKey", "PINLength", "0"):
                changed.append("LinkKey.PINLength")

        if self.ltk:
            sections = [s for s in LE_KEY_SECTIONS if info.has_section(s)] or [
                "LongTermKey",
                "PeripheralLongTermKey",
            ]
            for section in sections:
                if info.set(section, "Key", self.ltk.hex().upper()):
                    changed.append(f"{section}.Key")
                if self.rand is not None and info.set(section, "Rand", str(self.rand)):
                    changed.append(f"{section}.Rand")
                if self.ediv is not None and info.set(section, "EDiv", str(self.ediv)):
                    changed.append(f"{section}.EDiv")
                if info.get(section, "EncSize") is None:
                    info.set(section, "EncSize", str(self.enc_size or len(self.ltk)))
                if info.get(section, "Authenticated") is None:
                    info.set(section, "Authenticated", "0")

        if self.irk and info.set("IdentityResolvingKey", "Key", self.irk.hex().upper()):
            changed.append("IdentityResolvingKey.Key")

        if self.csrk:
            if info.set("LocalSignatureKey", "Key", self.csrk.hex().upper()):
                changed.append("LocalSignatureKey.Key")
            if info.get("LocalSignatureKey", "EncSize") is None:
                info.set("LocalSignatureKey", "EncSize", "16")
            if info.get("LocalSignatureKey", "Authenticated") is None:
                info.set("LocalSignatureKey", "Authenticated", "0")

        return changed

    def describe(self) -> str:
        kinds = []
        if self.link_key:
            kinds.append("BR/EDR")
        if self.is_le:
            kinds.append("LE")
        return f"{self.mac} ({'/'.join(kinds) or 'unknown'}){' ' + self.name if self.name else ''}"


# --------------------------------------------------------------------------
# Windows side
# --------------------------------------------------------------------------


def find_hive(windows_root: Path) -> Path | None:
    for candidate in HIVE_CANDIDATES:
        hive = windows_root / candidate
        if hive.is_file():
            return hive
    return None


def reged_export(hive: Path, key: str, destination: Path) -> None:
    """Export ``key`` of ``hive`` to ``destination`` (.reg text)."""
    command = ["reged", "-x", str(hive), r"HKEY_LOCAL_MACHINE\SYSTEM", key, str(destination)]
    result = subprocess.run(command, capture_output=True, text=True, timeout=120)
    if result.returncode != 0 or not destination.is_file():
        raise RuntimeError(
            f"reged failed for {key!r}: {result.stderr.strip() or result.stdout.strip() or 'no output'}"
        )


def current_control_set(hive: Path, scratch: Path) -> str:
    export = scratch / "select.reg"
    try:
        reged_export(hive, "Select", export)
    except RuntimeError:
        return f"{CONTROL_SET_PREFIX}001"
    for path, values in RegFile(export.read_text(errors="replace")).sections.items():
        if path.lower().rstrip("\\").endswith("select"):
            current = value_int(values.get("Current", ""))
            if current is not None and 0 < current < 1000:
                return f"{CONTROL_SET_PREFIX}{current:03d}"
    return f"{CONTROL_SET_PREFIX}001"


def read_bthport(hive: Path, scratch: Path, control_set: str) -> RegFile:
    export = scratch / "bthport.reg"
    reged_export(hive, f"{control_set}\\{BTHPORT_RELATIVE}", export)
    return RegFile(export.read_text(errors="replace"))


def resolve_mac(candidates: "list[str]", known: "set[str]") -> str:
    """Pick the reading of a registry address that matches a known address."""
    for candidate in candidates:
        if candidate in known:
            return candidate
    return candidates[0]


def collect_bonds(
    reg: RegFile,
    control_set: str,
    adapter_mac: str,
    known_addresses: "set[str]",
) -> "tuple[list[Bond], list[str]]":
    notes: "list[str]" = []
    prefix = f"{control_set}\\{BTHPORT_RELATIVE}\\Keys"
    keys = reg.relative(prefix)
    if not keys:
        return [], [f"no BTHPORT key store in {prefix}"]

    adapter_compact = compact_mac(adapter_mac)
    assert adapter_compact is not None
    adapter_variants = {adapter_compact, reverse_mac(adapter_compact)}

    adapter_name = next(
        (name for name in keys if compact_mac(name.rsplit("\\", 1)[-1]) in adapter_variants),
        None,
    )
    if adapter_name is None:
        found = ", ".join(sorted(keys)) or "none"
        notes.append(
            f"Windows has no pairing keys for adapter {adapter_mac} "
            f"(it knows about: {found})"
        )
        return [], notes
    if compact_mac(adapter_name.rsplit("\\", 1)[-1]) != adapter_compact:
        notes.append(f"adapter address is byte-reversed in the registry ({adapter_name})")

    bonds: "dict[str, Bond]" = {}

    def bond_for(raw_address: str) -> Bond | None:
        compact = compact_mac(raw_address)
        if not compact:
            return None
        mac = pretty_mac(resolve_mac([compact, reverse_mac(compact)], known_addresses))
        if mac not in bonds:
            bonds[mac] = Bond(mac)
        return bonds[mac]

    # Classic devices: a value named after the device holds the link key.
    for name, raw in keys[adapter_name].items():
        if name.lower() == "masterirk":  # the local adapter's own IRK
            continue
        bond = bond_for(name)
        if bond is None:
            continue
        data = value_bytes(raw)
        if not data:
            continue
        if len(data) != 16:
            notes.append(f"{bond.mac}: ignoring {len(data)}-byte classic key")
            continue
        bond.link_key = data

    # Bluetooth 5.1 LE devices: a subkey named after the device.
    for path, values in keys.items():
        if not path.startswith(adapter_name + "\\"):
            continue
        bond = bond_for(path[len(adapter_name) + 1 :].rsplit("\\", 1)[-1])
        if bond is None:
            continue
        bond.ltk = value_bytes(values.get("LTK", ""))
        bond.irk = value_bytes(values.get("IRK", ""))
        bond.csrk = value_bytes(values.get("CSRK", ""))
        bond.rand = value_int(values.get("ERand", ""))
        bond.ediv = value_int(values.get("EDIV", ""))
        enc_size = value_int(values.get("KeyLength", ""))
        if enc_size:
            bond.enc_size = enc_size
        address_type = value_int(values.get("AddressType", ""))
        if address_type is not None:
            bond.address_type = "public" if address_type == 0 else "static"
        # Some stacks keep the friendly name next to the keys instead of in the
        # sibling Devices key; take whichever place has it.
        if bond.name is None:
            bond.name = value_text(values.get("Name", ""))

    # Friendly names live in a sibling key, best effort only.
    devices = reg.relative(f"{control_set}\\{BTHPORT_RELATIVE}\\Devices")
    for bond in bonds.values():
        compact = compact_mac(bond.mac)
        assert compact is not None
        for name in (compact.lower(), reverse_mac(compact).lower()):
            values = devices.get(name) or devices.get(name + "\\" + name)
            if not values:
                continue
            for key in ("Name", "DeviceName", "FriendlyName"):
                text = value_text(values.get(key, ""))
                if text and text.strip():
                    bond.name = text.strip()
                    break
            if bond.name:
                break

    # A device whose only entry is junk (a truncated or unreadable key) must not
    # create a BlueZ device with no key material at all.
    kept = {mac: b for mac, b in bonds.items() if b.link_key or b.ltk or b.irk}
    for mac in sorted(set(bonds) - set(kept)):
        notes.append(f"{mac}: no usable pairing key in the registry, skipped")
    return [kept[mac] for mac in sorted(kept)], notes


# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------


def parse_args(argv: "list[str]") -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="dualboot-bt-import",
        description=(
            "Copy Bluetooth pairing keys from a dual-boot Windows installation "
            "into BlueZ's /var/lib/bluetooth store."
        ),
    )
    parser.add_argument(
        "--windows-root",
        default=DEFAULT_WINDOWS_ROOT,
        help=f"mount point of the Windows system volume (default: {DEFAULT_WINDOWS_ROOT})",
    )
    parser.add_argument(
        "--adapter",
        help="local Bluetooth adapter address; detected from the BlueZ store by default",
    )
    parser.add_argument(
        "--bluetooth-dir",
        default=DEFAULT_BLUETOOTH_DIR,
        help=f"BlueZ storage directory (default: {DEFAULT_BLUETOOTH_DIR})",
    )
    parser.add_argument(
        "--backup-dir",
        default=DEFAULT_BACKUP_DIR,
        help=f"where replaced info files are backed up (default: {DEFAULT_BACKUP_DIR})",
    )
    parser.add_argument("--dry-run", action="store_true", help="report changes, write nothing")
    parser.add_argument("--list", action="store_true", help="list what Windows has and exit")
    parser.add_argument(
        "--no-restart",
        action="store_true",
        help="do not restart bluetooth.service after writing (systemd runs this before bluetoothd)",
    )
    parser.add_argument(
        "--missing-ok",
        action="store_true",
        help="exit 0 when the Windows volume or its keys are unavailable (used at boot)",
    )
    return parser.parse_args(argv)


def fail(message: str, missing_ok: bool = False) -> int:
    print(f"dualboot-bt-import: {message}", file=sys.stderr)
    return 0 if missing_ok else 1


def detect_adapter(bluetooth_dir: Path) -> str | None:
    if not bluetooth_dir.is_dir():
        return None
    adapters = sorted(
        entry.name for entry in bluetooth_dir.iterdir() if entry.is_dir() and compact_mac(entry.name)
    )
    if len(adapters) == 1:
        return pretty_mac(compact_mac(adapters[0]) or adapters[0])
    return None


def main(argv: "list[str]") -> int:
    args = parse_args(argv)
    windows_root = Path(args.windows_root)
    bluetooth_dir = Path(args.bluetooth_dir)
    backup_root = Path(args.backup_dir)

    if os.geteuid() != 0:
        return fail("must run as root (BlueZ's pairing store is root-only)", args.missing_ok)

    if not bluetooth_dir.is_dir():
        return fail(f"{bluetooth_dir} does not exist", args.missing_ok)

    adapter = args.adapter or detect_adapter(bluetooth_dir)
    if not adapter:
        return fail(
            "cannot tell which Bluetooth adapter to use; pass --adapter <address> "
            f"(directories under {bluetooth_dir})",
            args.missing_ok,
        )
    if compact_mac(adapter) is None:
        return fail(f"{adapter!r} is not a Bluetooth address", args.missing_ok)

    hive = find_hive(windows_root)
    if hive is None:
        return fail(
            f"no Windows registry hive under {windows_root}; is the Windows volume "
            "mounted? (systemctl status mnt-windows.mount)",
            args.missing_ok,
        )

    # Work on a copy: reged may replay the hive's transaction logs, and a
    # read-only mount must never be written to.
    scratch = Path(tempfile.mkdtemp(prefix="dualboot-bt-"))
    try:
        scratch_hive = scratch / "SYSTEM"
        shutil.copy2(hive, scratch_hive)
        for suffix in (".LOG1", ".LOG2"):
            log = hive.with_name(hive.name + suffix)
            if log.is_file():
                shutil.copy2(log, scratch_hive.with_name(scratch_hive.name + suffix))

        control_set = current_control_set(scratch_hive, scratch)
        reg = read_bthport(scratch_hive, scratch, control_set)

        known: "set[str]" = set()
        adapter_dir = bluetooth_dir / adapter
        if adapter_dir.is_dir():
            for entry in adapter_dir.iterdir():
                compact = compact_mac(entry.name) if entry.is_dir() else None
                if compact:
                    known.add(compact)

        bonds, notes = collect_bonds(reg, control_set, adapter, known)
        for note in notes:
            print(f"dualboot-bt-import: {note}", file=sys.stderr)

        if not bonds:
            return fail("no Bluetooth pairings found on the Windows side", args.missing_ok)

        if args.list:
            for bond in bonds:
                print(bond.describe())
            return 0

        changes: "list[tuple[Bond, Path, InfoFile, list[str]]]" = []
        for bond in bonds:
            path = adapter_dir / bond.mac / "info"
            existing = path.read_text(errors="replace") if path.is_file() else ""
            info = InfoFile(existing)
            changed = bond.apply(info, create=not path.is_file())
            if changed:
                changes.append((bond, path, info, changed))

        if not changes:
            print(f"dualboot-bt-import: {len(bonds)} pairing(s) already in sync")
            return 0

        for bond, path, info, changed in changes:
            print(f"dualboot-bt-import: {bond.mac}: {', '.join(changed)}")

        if args.dry_run:
            print(f"dualboot-bt-import: dry run, {len(changes)} file(s) left untouched")
            return 0

        stamp = time.strftime("%Y-%m-%d_%H-%M-%S")
        for bond, path, info, _ in changes:
            if path.is_file():
                backup = backup_root / stamp / adapter / bond.mac / "info"
                backup.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, backup)
            path.parent.mkdir(parents=True, exist_ok=True)
            os.chmod(path.parent, 0o700)
            path.write_text(info.render())
            os.chmod(path, 0o600)
        print(f"dualboot-bt-import: wrote {len(changes)} file(s) into {adapter_dir}")

        if not args.no_restart:
            subprocess.run(["systemctl", "restart", "bluetooth.service"], check=False)
            print("dualboot-bt-import: restarted bluetooth.service")
        return 0
    finally:
        shutil.rmtree(scratch, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
