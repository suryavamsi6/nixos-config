#!/usr/bin/env python3
"""Add MangoWM's mmsg IPC as a Serpantinum compositor backend."""

from pathlib import Path
import sys


root = Path(sys.argv[1])


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one match, found {count}: {old[:80]!r}")
    path.write_text(text.replace(old, new))




def patch_workspace(path: Path, root_id: str, root_prefix: str) -> None:
    text = path.read_text()
    text = text.replace(
        "    property bool isSway: false\n",
        "    property bool isSway: false\n    property bool isMango: false\n",
        1,
    )
    text = text.replace(
        "    property var swayOccupiedMap: ({})\n",
        "    property var swayOccupiedMap: ({})\n    property int mangoActiveIndex: 0\n    property var mangoOccupiedMap: ({})\n",
        1,
    )
    text = text.replace(
        "if (isNiri || isSway) return null;",
        "if (isNiri || isSway || isMango) return null;",
        1,
    )
    text = text.replace(
        "        } else if (isSway) {\n            idx = swayActiveIndex;\n        } else {",
        "        } else if (isSway) {\n            idx = swayActiveIndex;\n        } else if (isMango) {\n            idx = mangoActiveIndex;\n        } else {",
        1,
    )
    text = text.replace(
        f'        {root_id}.isSway = de.indexOf("sway") !== -1;\n',
        f'        {root_id}.isSway = de.indexOf("sway") !== -1;\n        {root_id}.isMango = de.indexOf("mango") !== -1;\n',
        1,
    )
    text = text.replace(
        "        if (workspacesWidgetRoot.isSway && workspacesWidgetRoot.moduleActive) {\n            swayPoller.running = true;\n        }\n"
        if root_id == "workspacesWidgetRoot"
        else "        if (sideWsRoot.isSway && sideWsRoot.moduleActive) {\n            swayPoller.running = true;\n        }\n",
        f"        if ({root_id}.isSway && {root_id}.moduleActive) {{\n            swayPoller.running = true;\n        }}\n        if ({root_id}.isMango && {root_id}.moduleActive) {{\n            mangoPoller.running = true;\n        }}\n",
        1,
    )
    text = text.replace(
        "            if (isSway) {\n                swayPoller.running = false;\n                swayWaiter.running = false;\n            }\n",
        "            if (isSway) {\n                swayPoller.running = false;\n                swayWaiter.running = false;\n            }\n            if (isMango) {\n                mangoPoller.running = false;\n                mangoPollTimer.stop();\n            }\n",
        1,
    )
    text = text.replace(
        "            if (isSway) {\n                swayPoller.running = false;\n                swayPoller.running = true;\n            }\n        }\n    }\n",
        "            if (isSway) {\n                swayPoller.running = false;\n                swayPoller.running = true;\n            }\n            if (isMango) {\n                mangoPoller.running = false;\n                mangoPoller.running = true;\n            }\n        }\n    }\n",
        1,
    )
    marker = "    property real targetX: 0\n" if root_id == "workspacesWidgetRoot" else "    property real targetY: 0\n"
    mango_process = f'''    Timer {{
        id: mangoPollTimer
        interval: 750
        repeat: false
        onTriggered: {{
            if ({root_id}.moduleActive && {root_id}.isMango) mangoPoller.running = true;
        }}
    }}

    Process {{
        id: mangoPoller
        running: false
        command: ["mmsg", "get", "all-tags"]
        stdout: StdioCollector {{
            onStreamFinished: {{
                try {{
                    let data = JSON.parse(this.text);
                    let entries = data.all_tags || [];
                    let activeIdx = 0;
                    let occ = {{}};
                    for (let i = 0; i < entries.length; i++) {{
                        let tags = entries[i].tags || [];
                        for (let j = 0; j < tags.length; j++) {{
                            let tag = tags[j];
                            let idx = (tag.index || (j + 1)) - 1;
                            if (tag.is_active) activeIdx = idx;
                            if ((tag.client_count || 0) > 0) occ[idx] = true;
                        }}
                    }}
                    {root_id}.mangoActiveIndex = activeIdx;
                    {root_id}.mangoOccupiedMap = occ;
                }} catch (e) {{}}
                if ({root_id}.moduleActive && {root_id}.isMango) mangoPollTimer.restart();
            }}
        }}
    }}

'''
    if text.count(marker) != 1:
        raise SystemExit(f"{path}: target marker missing")
    text = text.replace(marker, mango_process + marker, 1)
    text = text.replace(
        f"                    if ({root_id}.isSway) {{\n                        return !!{root_id}.swayOccupiedMap[index];\n                    }}\n                    return ws !== null",
        f"                    if ({root_id}.isSway) {{\n                        return !!{root_id}.swayOccupiedMap[index];\n                    }}\n                    if ({root_id}.isMango) {{\n                        return !!{root_id}.mangoOccupiedMap[index];\n                    }}\n                    return ws !== null",
        1,
    )
    text = text.replace(
        f"                        }} else if ({root_id}.isSway) {{\n                            {root_id}.swayActiveIndex = nextIndex;\n                            Quickshell.execDetached([\"swaymsg\", \"workspace\", \"number\", (nextIndex + 1).toString()]);\n                        }} else {{",
        f"                        }} else if ({root_id}.isSway) {{\n                            {root_id}.swayActiveIndex = nextIndex;\n                            Quickshell.execDetached([\"swaymsg\", \"workspace\", \"number\", (nextIndex + 1).toString()]);\n                        }} else if ({root_id}.isMango) {{\n                            {root_id}.mangoActiveIndex = nextIndex;\n                            Quickshell.execDetached([\"mmsg\", \"dispatch\", \"view,\" + (nextIndex + 1).toString()]);\n                        }} else {{",
        1,
    )
    text = text.replace(
        f"                        }} else if ({root_id}.isSway) {{\n                            {root_id}.swayActiveIndex = wsPill.index;\n                            Quickshell.execDetached([\"swaymsg\", \"workspace\", \"number\", wsPill.wsId.toString()]);\n                        }} else {{",
        f"                        }} else if ({root_id}.isSway) {{\n                            {root_id}.swayActiveIndex = wsPill.index;\n                            Quickshell.execDetached([\"swaymsg\", \"workspace\", \"number\", wsPill.wsId.toString()]);\n                        }} else if ({root_id}.isMango) {{\n                            {root_id}.mangoActiveIndex = wsPill.index;\n                            Quickshell.execDetached([\"mmsg\", \"dispatch\", \"view,\" + wsPill.wsId.toString()]);\n                        }} else {{",
        1,
    )
    path.write_text(text)


patch_workspace(root / "quickshell/bar/modules/WorkspacesWidget.qml", "workspacesWidgetRoot", "")
patch_workspace(root / "quickshell/bar/sidemodules/SideWorkspacesWidget.qml", "sideWsRoot", "")

for relative in (
    "quickshell/bar/modules/system/KbWidget.qml",
    "quickshell/bar/sidemodules/system/SideKbWidget.qml",
):
    path = root / relative
    text = path.read_text()
    text = text.replace(
        "    property bool isSway: false\n",
        "    property bool isSway: false\n    property bool isMango: false\n",
        1,
    )
    text = text.replace(
        '        kbWidgetRoot.isSway = de.indexOf("sway") !== -1;\n',
        '        kbWidgetRoot.isSway = de.indexOf("sway") !== -1;\n        kbWidgetRoot.isMango = de.indexOf("mango") !== -1;\n',
        1,
    ) if "KbWidget.qml" in relative and "SideKb" not in relative else text.replace(
        '        sideKbRoot.isSway = de.indexOf("sway") !== -1;\n',
        '        sideKbRoot.isSway = de.indexOf("sway") !== -1;\n        sideKbRoot.isMango = de.indexOf("mango") !== -1;\n',
        1,
    )
    root_id = "kbWidgetRoot" if "SideKb" not in relative else "sideKbRoot"
    old = (
        f'            {root_id}.isNiri\n'
        f'                ? "layout=$(niri msg -j keyboard-layouts 2>/dev/null | jq -r \' .names[.current_idx] // empty\' | head -n1); [[ -z \\"$layout\\" || \\"$layout\\" == \\"null\\" ]] && layout=\\"US\\"; echo \\"${{layout:0:2}}\\" | tr \'[:lower:]\' \'[:upper:]\'"'
    )
    # Avoid matching shell quoting variants by inserting the Mango arm before isNiri.
    needle = f'            {root_id}.isNiri\n'
    mango_arm = f'            {root_id}.isMango\n                ? "layout=$(mmsg get keyboardlayout 2>/dev/null | jq -r \' .layout // empty\' | head -n1); [[ -z \\"$layout\\" || \\"$layout\\" == \\"null\\" ]] && layout=\\"US\\"; echo \\"${{layout:0:2}}\\" | tr \'[:lower:]\' \'[:upper:]\'"\n                : '
    if text.count(needle) != 1:
        raise SystemExit(f"{path}: keyboard ternary target missing")
    text = text.replace(needle, mango_arm + needle.lstrip(), 1)
    text = text.replace(
        f'            {root_id}.isNiri ? "niri" : ({root_id}.isSway ? "sway" : "hyprland")',
        f'            {root_id}.isMango ? "mango" : ({root_id}.isNiri ? "niri" : ({root_id}.isSway ? "sway" : "hyprland"))',
        1,
    )
    text = text.replace(
        f'                if ({root_id}.isNiri) {{',
        f'                if ({root_id}.isMango) {{\n                    Quickshell.execDetached(["mmsg", "dispatch", "switch_keyboard_layout"]);\n                }} else if ({root_id}.isNiri) {{',
        1,
    )
    path.write_text(text)

replace_once(
    root / "quickshell/watchers/kb_wait.sh",
    "case \"$COMPOSITOR\" in\n    niri)",
    'case "$COMPOSITOR" in\n    mango)\n        mmsg watch keyboardlayout 2>/dev/null > "$PIPE" &\n        ;;\n    niri)',
)

idle = root / "quickshell/idle/Idle.qml"
replace_once(
    idle,
    "    property bool isNiri: {\n",
    '    property bool isMango: {\n        let de = (typeof SystemInfo !== "undefined" && SystemInfo.desktopEnv) ? SystemInfo.desktopEnv.toLowerCase() : "";\n        let xdg = (typeof Quickshell !== "undefined" && Quickshell.env) ? (Quickshell.env("XDG_CURRENT_DESKTOP") || "") : "";\n        return de.indexOf("mango") !== -1 || xdg.toLowerCase().indexOf("mango") !== -1;\n    }\n\n    property bool isNiri: {\n',
)
replace_once(
    idle,
    "    function dpmsOff() {\n        if (idleRoot.isNiri) {",
    '    function dpmsOff() {\n        if (idleRoot.isMango) {\n            Quickshell.execDetached(["mmsg", "dispatch", "sleep_monitor"]);\n        } else if (idleRoot.isNiri) {',
)
replace_once(
    idle,
    "    function dpmsOn() {\n        if (idleRoot.isNiri) {",
    '    function dpmsOn() {\n        if (idleRoot.isMango) {\n            Quickshell.execDetached(["mmsg", "dispatch", "wakeup_monitor"]);\n        } else if (idleRoot.isNiri) {',
)
