#!/usr/bin/env python3
"""Apply the Serpantinum World Clock integration to a built package tree.

The patch is deliberately fail-closed: the supported version and every target
file are fingerprinted before the first edit. A fully patched tree is accepted
as an idempotent no-op; a partially patched tree is rejected.
"""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import tempfile
from typing import Callable

EXPECTED_HASHES = {
    "quickshell/guide/BarTab.qml": "7c6b38dd22642ba2bb349adf586ad25563e45b424dc6d6e4e55a6473fd621090",
    "quickshell/guide/GuidePopup.qml": "5e16b31d0c62727b62fa065b6ca3d623411cb8fcc1350e760affc6e3d057efd8",
    "quickshell/bar/TopBar.qml": "65ff6db2a409860b45605c2266a0dea4200281b3fef5459e1a82445930cd6a4b",
    "quickshell/WindowRegistry.js": "d16d081df66191d00816f69f76e94e42079db406913d7d06ad15dce9c066bf19",
    "quickshell/Main.qml": "657b8acee56e8ab33c4baf855b69c8f0475b70cfda1ce0b438a008cbf5d5c01d",
    "quickshell/qmldir": "41ef3bc2341fea7cdd3bb6d39241d186687b46692191434e91d4009914861665",
    "quickshell/bar/modules/qmldir": "1c1bcabcf88f81c5caeeb8af11962231a9fdc44d20c3a40c54fd5b9a143d66ee",
    "assets/languages/en.json": "68ed820bc1d3842ebff6ef040952d77c5a53cf2c50da8a1e1521adfbeb9a1f59",
}


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one exact anchor, found {count}")
    return text.replace(old, new, 1)


def patch_bar_tab(text: str) -> str:
    label = "quickshell/guide/BarTab.qml"
    text = replace_once(
        text,
        "    function getModuleInfo(id) {\n",
        "    // serpantinum-world-clock: module registration\n    function getModuleInfo(id) {\n",
        label,
    )
    text = replace_once(text, '            "timedate": I18n.t("guide.bar.modules.timedate"),\n', '            "timedate": I18n.t("guide.bar.modules.timedate"),\n            "worldclock": I18n.t("guide.bar.modules.worldclock"),\n', label)
    text = replace_once(text, '            "timedate": "󰃰",\n', '            "timedate": "󰃰",\n            "worldclock": "󰖟",\n', label)
    text = replace_once(text, '            "timedate": ThemeBackend.peach,\n', '            "timedate": ThemeBackend.peach,\n            "worldclock": ThemeBackend.sapphire,\n', label)
    text = replace_once(text, '        let allKeys = ["left", "workspaces", "focus", "timedate", "info", "weather",', '        let allKeys = ["left", "workspaces", "focus", "timedate", "worldclock", "info", "weather",', label)
    text = replace_once(text, '                            if (moduleId === "timedate") return I18n.t("guide.bar.modules.timedate");\n', '                            if (moduleId === "timedate") return I18n.t("guide.bar.modules.timedate");\n                            if (moduleId === "worldclock") return I18n.t("guide.bar.modules.worldclock");\n', label)
    return text


def patch_guide_popup(text: str) -> str:
    return replace_once(
        text,
        '        { id: "Bar", key: "bar", name: "Bar", icon: "󰹑", file: "BarTab.qml" },\n',
        '        { id: "Bar", key: "bar", name: "Bar", icon: "󰹑", file: "BarTab.qml" },\n        // serpantinum-world-clock: dedicated settings page\n        { id: "WorldClock", key: "world_clock", name: "World Clock", icon: "󰖟", file: "worldclock/WorldClockTab.qml" },\n',
        "quickshell/guide/GuidePopup.qml",
    )


def patch_top_bar(text: str) -> str:
    label = "quickshell/bar/TopBar.qml"
    text = replace_once(
        text,
        '    property real wTimedate: isModuleActive("timedate") ? (timeDateWidget.targetWidth !== undefined ? timeDateWidget.targetWidth : timeDateWidget.width) : 0\n',
        '    property real wTimedate: isModuleActive("timedate") ? (timeDateWidget.targetWidth !== undefined ? timeDateWidget.targetWidth : timeDateWidget.width) : 0\n    // serpantinum-world-clock: layout width\n    property real wWorldClock: isModuleActive("worldclock") ? (worldClockWidget.targetWidth !== undefined ? worldClockWidget.targetWidth : worldClockWidget.width) : 0\n',
        label,
    )
    text = replace_once(text, '        if (moduleId === "timedate" || moduleId === "time" || moduleId === "clock") return wTimedate;\n', '        if (moduleId === "timedate" || moduleId === "time" || moduleId === "clock") return wTimedate;\n        if (moduleId === "worldclock") return wWorldClock;\n', label)
    text = replace_once(text, '        if (id === "timedate" || id === "time" || id === "clock") return timeDateWidget;\n', '        if (id === "timedate" || id === "time" || id === "clock") return timeDateWidget;\n        if (id === "worldclock") return worldClockWidget;\n', label)
    text = replace_once(text, '        else if (widgetName === "timedate" || widgetName === "time" || widgetName === "clock") return timeDateWidget;\n', '        else if (widgetName === "timedate" || widgetName === "time" || widgetName === "clock") return timeDateWidget;\n        else if (widgetName === "worldclock") return worldClockWidget;\n', label)
    widget = '''    // serpantinum-world-clock: bar widget instance
    WorldClockWidget {
        id: worldClockWidget
        z: 10
        x: targetX
        y: contentWrapper.getModuleY(worldClockWidget)
        visible: contentWrapper.isModuleActive("worldclock")
        barWindow: contentWrapper.barWindow
        isSolid: contentWrapper.isSolid || contentWrapper.isFill
        distinctPills: contentWrapper.distinctPills
        moduleActive: contentWrapper.isModuleActive("worldclock")
        isGrouped: contentWrapper.isModuleGrouped("worldclock")
        targetX: contentWrapper.getModuleX("worldclock", contentWrapper.layoutState)

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        Behavior on x {
            enabled: contentWrapper.layoutAnimationsEnabled
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
    }

'''
    text = replace_once(text, "    InfoWidget {\n", widget + "    InfoWidget {\n", label)
    return text


def patch_registry(text: str) -> str:
    label = "quickshell/WindowRegistry.js"
    launcher = '''        // serpantinum-world-clock: launcher entry
        {
            id: "worldclock",
            name: tr("widgets.worldclock.name", "World Clock"),
            description: tr("widgets.worldclock.desc", "View times around the world"),
            icon: "preferences-system-time",
            fontIcon: "󰖟"
        },
'''
    text = replace_once(text, '        {\n            id: "calendar",\n', launcher + '        {\n            id: "calendar",\n', label)
    layout = '''        // serpantinum-world-clock: popup layout
        "worldclock": {
            w: 1080, h: 620, comp: "worldclock/WorldClockPanel.qml",
            pos: {
                "top": { anchor: "top-center", mt: 52 },
                "bottom": { anchor: "bottom-center", mb: 52 },
                "left": { anchor: "top-center", mt: 12 },
                "right": { anchor: "top-center", mt: 12 }
            }
        },
'''
    text = replace_once(text, '        "calendar": { \n', layout + '        "calendar": { \n', label)
    return text


def patch_main(text: str) -> str:
    return replace_once(
        text,
        '    property var _allWidgetNames: ["battery", "network", "volume", "guide", "calendar", "wallpaper",',
        '    // serpantinum-world-clock: preload cached popup\n    property var _allWidgetNames: ["battery", "network", "volume", "guide", "calendar", "worldclock", "wallpaper",',
        "quickshell/Main.qml",
    )

def patch_root_qmldir(text: str) -> str:
    return replace_once(
        text,
        "singleton DateTime 1.0 singletons/DateTime.qml\n",
        "singleton DateTime 1.0 singletons/DateTime.qml\n# serpantinum-world-clock: shared service\nsingleton WorldClockService 1.0 singletons/WorldClockService.qml\n",
        "quickshell/qmldir",
    )


def patch_modules_qmldir(text: str) -> str:
    return replace_once(
        text,
        "TimeDateWidget 1.0 TimeDateWidget.qml \n",
        "TimeDateWidget 1.0 TimeDateWidget.qml \n# serpantinum-world-clock: bar type\nWorldClockWidget 1.0 WorldClockWidget.qml\n",
        "quickshell/bar/modules/qmldir",
    )


def patch_english(text: str) -> str:
    label = "assets/languages/en.json"
    text = replace_once(text, '      "bar": "Bar",\n', '      "bar": "Bar",\n      "world_clock": "World Clock",\n', label)
    text = replace_once(text, '        "timedate": "Time/date",\n', '        "timedate": "Time/date",\n        "worldclock": "World clock",\n', label)
    settings = '''    "world_clock": {
      "title": "World Clock",
      "description": "Choose the cities shown on the globe and configure its motion.",
      "saved_cities": "Saved cities",
      "add_city": "Add a city",
      "search_placeholder": "Search a city or IANA timezone...",
      "searching": "Searching...",
      "no_results": "No matching cities",
      "online_result": "Online result",
      "online_search": "Use online search fallback",
      "online_search_desc": "Send the query to Open-Meteo only when the offline catalogue has no match.",
      "personal_label": "Personal label (optional)",
      "add": "Add",
      "remove": "Remove",
      "move_up": "Move up",
      "move_down": "Move down",
      "time_format": "Time format",
      "follow_bar": "Follow bar",
      "twelve_hour": "12-hour",
      "twenty_four_hour": "24-hour",
      "auto_rotate": "Auto-rotate globe",
      "rotation_speed": "Rotation speed"
    },
'''
    text = replace_once(text, '    "theme": {\n', settings + '    "theme": {\n', label)
    panel = '''  "worldclock": {
    "title": "World Clock",
    "settings": "World Clock settings",
    "empty_title": "No cities configured",
    "empty_body": "Add cities in Settings to place them on the globe.",
    "open_settings": "Open Settings",
    "loading": "Updating world times...",
    "backend_error": "World Clock could not update",
    "today": "Today",
    "yesterday": "Yesterday",
    "tomorrow": "Tomorrow"
  },
'''
    panel_anchor = '''  "applauncher": {
    "search": "Search",
    "placeholder": "Start with > for a command..."
  },
  "calendar": {
'''
    panel_prefix = panel_anchor[:-len('  "calendar": {\n')]
    text = replace_once(text, panel_anchor, panel_prefix + panel + '  "calendar": {\n', label)
    widget = '''    "worldclock": {
      "name": "World clock",
      "desc": "View local times on a 3D Earth"
    },
'''
    text = replace_once(text, '    "calendar": {\n      "name": "Calendar & clock",\n', widget + '    "calendar": {\n      "name": "Calendar & clock",\n', label)
    return text


PATCHERS: dict[str, Callable[[str], str]] = {
    "quickshell/guide/BarTab.qml": patch_bar_tab,
    "quickshell/guide/GuidePopup.qml": patch_guide_popup,
    "quickshell/bar/TopBar.qml": patch_top_bar,
    "quickshell/WindowRegistry.js": patch_registry,
    "quickshell/Main.qml": patch_main,
    "quickshell/qmldir": patch_root_qmldir,
    "quickshell/bar/modules/qmldir": patch_modules_qmldir,
    "assets/languages/en.json": patch_english,
}

POSTCHECKS = {
    "quickshell/guide/BarTab.qml": ["serpantinum-world-clock: module registration", '"worldclock": I18n.t("guide.bar.modules.worldclock")', '"timedate", "worldclock", "info"'],
    "quickshell/guide/GuidePopup.qml": ["serpantinum-world-clock: dedicated settings page", 'file: "worldclock/WorldClockTab.qml"'],
    "quickshell/bar/TopBar.qml": ["serpantinum-world-clock: layout width", "WorldClockWidget {", 'getModuleX("worldclock"'],
    "quickshell/WindowRegistry.js": ["serpantinum-world-clock: launcher entry", 'comp: "worldclock/WorldClockPanel.qml"'],
    "quickshell/Main.qml": ["serpantinum-world-clock: preload cached popup", '"calendar", "worldclock", "wallpaper"'],
    "quickshell/qmldir": ["serpantinum-world-clock: shared service", "singleton WorldClockService 1.0 singletons/WorldClockService.qml"],
    "quickshell/bar/modules/qmldir": ["serpantinum-world-clock: bar type", "WorldClockWidget 1.0 WorldClockWidget.qml"],
    "assets/languages/en.json": ['"world_clock": "World Clock"', '"worldclock": {', '"backend_error": "World Clock could not update"'],
}


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def atomic_write(path: Path, text: str) -> None:
    mode = path.stat().st_mode
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", newline="", dir=path.parent, delete=False) as handle:
        handle.write(text)
        temp_name = handle.name
    os.chmod(temp_name, mode)
    os.replace(temp_name, path)


def apply(root: Path, expected_version: str, expected_revision: str) -> list[str]:
    version_path = root / "version.txt"
    if not version_path.is_file():
        raise RuntimeError(f"missing Serpantinum version file: {version_path}")
    actual_version = version_path.read_text(encoding="utf-8").strip()
    if actual_version != expected_version:
        raise RuntimeError(
            f"unsupported Serpantinum version {actual_version!r}; expected {expected_version!r} "
            f"at revision {expected_revision}"
        )

    pending: list[tuple[Path, str]] = []
    states: list[str] = []
    for relative, patcher in PATCHERS.items():
        path = root / relative
        if not path.is_file():
            raise RuntimeError(f"missing Serpantinum integration file: {path}")
        raw = path.read_bytes()
        text = raw.decode("utf-8")
        checks = POSTCHECKS[relative]
        matches = [check in text for check in checks]
        if all(matches):
            states.append(f"already patched: {relative}")
            continue
        if any(matches):
            raise RuntimeError(f"refusing partially patched file: {relative}")
        actual_hash = sha256(raw)
        expected_hash = EXPECTED_HASHES[relative]
        if actual_hash != expected_hash:
            raise RuntimeError(
                f"unsupported {relative} for Serpantinum revision {expected_revision}: "
                f"sha256 {actual_hash}, expected {expected_hash}"
            )
        patched = patcher(text)
        missing = [check for check in checks if check not in patched]
        if missing:
            raise RuntimeError(f"postcondition failed for {relative}: {missing}")
        pending.append((path, patched))
        states.append(f"patched: {relative}")

    for path, patched in pending:
        atomic_write(path, patched)
    return states


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--expected-version", required=True)
    parser.add_argument("--expected-revision", required=True)
    args = parser.parse_args()
    for state in apply(args.root, args.expected_version, args.expected_revision):
        print(state)


if __name__ == "__main__":
    main()
