#!/usr/bin/env python3
"""Show occupied numbered workspaces and keep top-bar module positions stable."""

from pathlib import Path
import sys


path = Path(sys.argv[1])
text = path.read_text()


def replace_once(old: str, new: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one match, found {count}: {old[:80]!r}")
    text = text.replace(old, new, 1)


replace_once(
    "    property real targetWidth: (moduleActive && workspaceCount > 0) ? wsLayout.implicitWidth + barWindow.s(isCompact ? 18 : 22) : 0\n",
    "    property real targetWidth: (moduleActive && wsLayout.implicitWidth > 0) ? wsLayout.implicitWidth + barWindow.s(isCompact ? 18 : 22) : 0\n",
)
replace_once(
    "    opacity: (moduleActive && workspaceCount > 0) ? ((barWindow && barWindow.barOpacity !== undefined) ? barWindow.barOpacity : 1.0) : 0.0\n",
    "    opacity: (moduleActive && wsLayout.implicitWidth > 0) ? ((barWindow && barWindow.barOpacity !== undefined) ? barWindow.barOpacity : 1.0) : 0.0\n",
)
replace_once(
    "        z: 3\n        radius: barWindow.s(workspacesWidgetRoot.isCompact ? 7 : 8)\n",
    "        z: 3\n        visible: false\n        radius: barWindow.s(workspacesWidgetRoot.isCompact ? 7 : 8)\n",
)
replace_once(
    "        spacing: barWindow.s(workspacesWidgetRoot.isCompact ? 7 : 8)\n",
    "        spacing: barWindow.s(6)\n",
)
replace_once(
    "                width: isActive ? barWindow.s(workspacesWidgetRoot.isCompact ? 34 : 36) : barWindow.s(workspacesWidgetRoot.isCompact ? 16 : 18)\n"
    "                height: barWindow.s(workspacesWidgetRoot.isCompact ? 16 : 18)\n"
    "                anchors.verticalCenter: parent.verticalCenter\n",
    "                width: isOccupied ? barWindow.s(28) : 0\n"
    "                height: barWindow.s(24)\n"
    "                anchors.verticalCenter: parent.verticalCenter\n"
    "                visible: isOccupied\n",
)
replace_once(
    '                    color: wsPill.isActive ? "transparent" : (wsPill.isOccupied ? ThemeBackend.surface2 : (workspacesWidgetRoot.isCompact ? ThemeBackend.surface1 : ThemeBackend.surface0))\n',
    "                    color: wsPill.isActive ? ThemeBackend.mauve : (wsPillMouse.containsMouse ? Qt.alpha(ThemeBackend.text, 0.22) : Qt.alpha(ThemeBackend.text, 0.15))\n",
)
replace_once(
    "                }\n\n                opacity: initAnimTrigger ? 1.0 : 0.0\n",
    "                }\n\n"
    "                Text {\n"
    "                    anchors.centerIn: parent\n"
    "                    text: wsPill.wsId.toString()\n"
    "                    color: wsPill.isActive ? ThemeBackend.base : ThemeBackend.text\n"
    "                    font.family: \"JetBrains Mono\"\n"
    "                    font.pixelSize: barWindow.s(13)\n"
    "                    font.weight: wsPill.isActive ? Font.Black : Font.Bold\n"
    "                }\n\n"
    "                opacity: initAnimTrigger ? 1.0 : 0.0\n",
)

path.write_text(text)

path = Path(sys.argv[2])
text = path.read_text()
replace_once(
    '    property string layoutState: {\n'
    '        if (isFill) return "default";\n'
    '        if (barWindow && barWindow.isNotifOpen) return "settings";\n'
    '        if (barWindow && barWindow.isSysOpen) return "sys";\n'
    '        return "default";\n'
    '    }\n',
    '    property string layoutState: "default"\n',
)
path.write_text(text)
