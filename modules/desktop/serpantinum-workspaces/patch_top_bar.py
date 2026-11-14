#!/usr/bin/env python3
"""Pin the top bar's layout state so modules stop shifting when popups open.

Upstream's `layoutState` flips to "settings" or "sys" while the notification or
system popup is open, and eight consumers in TopBar.qml re-offset the bar when it
does (lines ~374-375, 403-404, 417, 429, 835): the right module cluster slides,
the center recenters on sysBoundary, and module X positions are recomputed.

Pinning it to "default" keeps every module where the user put it.

This replaces the old `patch_top_bar.py`, which also rewrote the workspace pill
geometry. That half was dropped: Serpantinum 2.3.x renders workspaces through
pluggable faces (`BarModuleRegistry.variantFaceFile`), and the "numbered pills,
occupied only" design the old patch hand-rolled is now the shipped `numbers`
face. Select it with `bar.workspacesStyle = "numbers"` instead of patching QML.

Anchored on Serpantinum v2.3.2 (commit d282c4c018).
"""
from pathlib import Path
import sys


path = Path(sys.argv[1])
text = path.read_text()

old = """    property string layoutState: {
        if (isFill) return "default";
        if (barWindow && barWindow.isNotifOpen) return "settings";
        if (barWindow && barWindow.isSysOpen) return "sys";
        return "default";
    }
"""
new = """    property string layoutState: "default"
"""

count = text.count(old)
if count != 1:
    raise SystemExit(f"TopBar layoutState: expected one match, found {count}")

path.write_text(text.replace(old, new, 1))
