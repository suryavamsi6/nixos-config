#!/usr/bin/env python3
"""Apply the small, revision-pinned Serpantinum integration patch."""
from __future__ import annotations

import pathlib
import sys


def patch(path: pathlib.Path, replacements: list[tuple[str, str]]) -> None:
    text = path.read_text()
    for old, new in replacements:
        if old not in text:
            raise SystemExit(f"world-clock patch anchor missing or already patched: {path}: {old[:100]!r}")
        text = text.replace(old, new, 1)
    path.write_text(text)


root = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path.cwd()
qs = root / "share/serpantinum/quickshell"

patch(
    qs / "bar/modules/TimeDateWidget.qml",
    [
        ('import "../../"\n\nRectangle {', 'import "../../"\n\nRectangle {'),
    ],
)
patch(
    qs / "bar/modules/qmldir",
    [("TimeDateWidget 1.0 TimeDateWidget.qml", "TimeDateWidget 1.0 TimeDateWidget.qml\nWorldClockButton 1.0 worldclock/WorldClockButton.qml")],
)
patch(
    qs / "bar/TopBar.qml",
    [
        ('        if (moduleId === "timedate") return flatLeftArr.indexOf("timedate") !== -1 || flatCenterArr.indexOf("timedate") !== -1 || flatRightArr.indexOf("timedate") !== -1 || flatLeftArr.indexOf("time") !== -1 || flatCenterArr.indexOf("time") !== -1 || flatRightArr.indexOf("time") !== -1 || flatLeftArr.indexOf("clock") !== -1 || flatCenterArr.indexOf("clock") !== -1 || flatRightArr.indexOf("clock") !== -1;','        if (moduleId === "timedate") return flatLeftArr.indexOf("timedate") !== -1 || flatCenterArr.indexOf("timedate") !== -1 || flatRightArr.indexOf("timedate") !== -1 || flatLeftArr.indexOf("time") !== -1 || flatCenterArr.indexOf("time") !== -1 || flatRightArr.indexOf("time") !== -1 || flatLeftArr.indexOf("clock") !== -1 || flatCenterArr.indexOf("clock") !== -1 || flatRightArr.indexOf("clock") !== -1;\n        if (moduleId === "worldclock") return flatLeftArr.indexOf("worldclock") !== -1 || flatCenterArr.indexOf("worldclock") !== -1 || flatRightArr.indexOf("worldclock") !== -1;'),
        ('    property real wTimedate: isModuleActive("timedate") ? (timeDateWidget.targetWidth !== undefined ? timeDateWidget.targetWidth : timeDateWidget.width) : 0','    property real wTimedate: isModuleActive("timedate") ? (timeDateWidget.targetWidth !== undefined ? timeDateWidget.targetWidth : timeDateWidget.width) : 0\n    property real wWorldclock: isModuleActive("worldclock") ? (worldClockWidget.targetWidth !== undefined ? worldClockWidget.targetWidth : worldClockWidget.width) : 0'),
        ('        if (moduleId === "timedate" || moduleId === "time" || moduleId === "clock") return wTimedate;','        if (moduleId === "timedate" || moduleId === "time" || moduleId === "clock") return wTimedate;\n        if (moduleId === "worldclock") return wWorldclock;'),
        ('        if (id === "timedate" || id === "time" || id === "clock") return timeDateWidget;','        if (id === "timedate" || id === "time" || id === "clock") return timeDateWidget;\n        if (id === "worldclock") return worldClockWidget;'),
        ('        else if (widgetName === "timedate" || widgetName === "time" || widgetName === "clock") return timeDateWidget;','        else if (widgetName === "timedate" || widgetName === "time" || widgetName === "clock") return timeDateWidget;\n        else if (widgetName === "worldclock") return worldClockWidget;'),
        ('    TimeDateWidget {','    WorldClockButton {\n        id: worldClockWidget\n        z: 10\n        visible: contentWrapper.isModuleActive("worldclock")\n        barWindow: contentWrapper.barWindow\n        moduleActive: contentWrapper.isModuleActive("worldclock")\n        targetX: contentWrapper.getModuleX("worldclock", contentWrapper.layoutState)\n    }\n\n    TimeDateWidget {'),
    ],
)
patch(
    qs / "guide/BarTab.qml",
    [
        ('            "bat": I18n.t("guide.bar.modules.battery")\n        };', '            "bat": I18n.t("guide.bar.modules.battery"),\n            "worldclock": "World clock"\n        };'),
        ('            "bat": "󰁹"\n        };', '            "bat": "󰁹",\n            "worldclock": "󰥔"\n        };'),
        ('            "bat": ThemeBackend.green\n        };', '            "bat": ThemeBackend.green,\n            "worldclock": ThemeBackend.peach\n        };'),
        ('let allKeys = ["left", "workspaces", "focus", "timedate", "info", "weather", "media", "vis", "tray", "sysmon", "kb", "wifi", "bt", "vol", "bat"];', 'let allKeys = ["left", "workspaces", "focus", "timedate", "info", "weather", "media", "vis", "tray", "sysmon", "kb", "wifi", "bt", "vol", "bat", "worldclock"];'),
        ('                            if (moduleId === "bat") return I18n.t("guide.bar.modules.battery");\n                            return model.moduleLabel !== undefined ? model.moduleLabel : moduleId;', '                            if (moduleId === "bat") return I18n.t("guide.bar.modules.battery");\n                            if (moduleId === "worldclock") return "World clock";\n                            return model.moduleLabel !== undefined ? model.moduleLabel : moduleId;'),
    ],
)
patch(
    qs / "WindowRegistry.js",
    [
        ('        "calendar": {', '        "worldclock": {\n            w: 1180, h: 640, comp: "worldclock/WorldClockPopup.qml",\n            pos: {\n                "top": { anchor: "top-center", mt: 52 },\n                "bottom": { anchor: "bottom-center", mb: 52 },\n                "left": { anchor: "center" },\n                "right": { anchor: "center" }\n            }\n        },\n        "calendar": {'),
    ],
)
patch(
    qs / "Main.qml",
    [( '"calendar", "wallpaper"', '"calendar", "worldclock", "wallpaper"')],
)
