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
        ('import "../../"\n\nRectangle {', 'import "../../"\nimport "worldclock"\n\nRectangle {'),
        ('property real baseWidth: timeCol.width + (horizontalPadding * 2)', 'property real baseWidth: timeCol.width + (horizontalPadding * 2) + worldClockButton.implicitWidth + barWindow.s(4)'),
        ('        height: barWindow ? barWindow.barHeight : 30\n        y: timeDateRoot.isBottomBar ? (parent.height - height) : 0\n\n        Column {', '        height: barWindow ? barWindow.barHeight : 30\n        y: timeDateRoot.isBottomBar ? (parent.height - height) : 0\n\n        WorldClockButton {\n            id: worldClockButton\n            anchors.right: parent.right\n            anchors.rightMargin: timeDateRoot.horizontalPadding\n            anchors.verticalCenter: parent.verticalCenter\n            barWindow: timeDateRoot.barWindow\n            moduleActive: timeDateRoot.moduleActive\n        }\n\n        Column {'),
    ],
)

patch(
    qs / "bar/modules/qmldir",
    [("TimeDateWidget 1.0 TimeDateWidget.qml", "TimeDateWidget 1.0 TimeDateWidget.qml\nWorldClockButton 1.0 worldclock/WorldClockButton.qml")],
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
