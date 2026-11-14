#!/usr/bin/env python3
"""Keep the Bluetooth bar pill visible on desktops (machines without a battery).

Serpantinum 2.3.x hides the Bluetooth bar face on any host whose
/sys/class/power_supply has no BAT* entry. BtFace.qml detects that at runtime
(`chassisDetector` echoes "laptop" or "desktop") and then collapses the module:

    :226  if (root.isDesktop) return 0;                                   # targetLength
    :232  property bool isFaceVisible: showLayout && !isDesktop && ...    # visibility
    :332  property real targetWidth: (root.isDesktop || ...) ? 0 : ...    # pill width

On a desktop that means the pill renders at zero width and disappearing,
even though Bluetooth is enabled and the module is active — the tray still
lists it, but the bar shows nothing.

This patch drops the `isDesktop` gates so the face is governed by the normal
`showIcon` / `showName` settings, which both default to true. Setting either
still collapses the face, and `moduleActive = false` still disables it.

Anchored on Serpantinum v2.3.2 (commit d282c4c018).
"""
from pathlib import Path
import sys


path = Path(sys.argv[1])
text = path.read_text()


def replace_once(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    text = text.replace(old, new, 1)


# 1. targetLength: only collapse when both icon and name are hidden.
replace_once(
    "        if (root.isDesktop) return 0;\n",
    "        if (root.isDesktop && !root.showIcon && !root.showName) return 0;\n",
    "targetLength desktop gate",
)

# 2. The face is visible whenever the layout says so and it has length.
replace_once(
    "    property bool isFaceVisible: showLayout && !isDesktop && targetLength > 0\n",
    "    property bool isFaceVisible: showLayout && targetLength > 0\n",
    "isFaceVisible desktop gate",
)

# 3. The pill's own width: drop the desktop clause, keep the icon/name one.
replace_once(
    "            property real targetWidth: (root.isDesktop || (!root.showIcon && !root.showName)) ? 0 : implicitWidth\n",
    "            property real targetWidth: (!root.showIcon && !root.showName) ? 0 : implicitWidth\n",
    "targetWidth desktop gate",
)

path.write_text(text)
