#!/usr/bin/env python3
"""Add the UPS page to Serpantinum's Settings sidebar.

The tab is inserted right after the Bar section. In 2.3.x that section is a
multi-line object (id/key/name spread over separate lines, with `subtabs`), so
the old single-line `id: "Bar", key: "bar", name: "Bar"` anchor no longer
matches. This anchors on the block's closing `},` following the subtabs list
instead, which is stable regardless of how the fields are wrapped.

Anchored on Serpantinum v2.3.2 (commit d282c4c018).
"""

import argparse
from pathlib import Path

SENTINEL = "UPS_SETTINGS_TAB_PATCH_V1"

# The Bar section ends with the subtabs array followed by the closing brace.
# Match the tail of that block so we can insert after it.
ANCHOR = """                { id: "BarModules", key: "bar_modules", name: "Modules", icon: "󰐱", file: "bar/BarModulesTab.qml" }
            ]
        },
"""

UPS_TAB = """        // UPS_SETTINGS_TAB_PATCH_V1
        { id: "UPS", key: "ups", name: "UPS", icon: "󰁯", file: "UpsTab.qml" },
"""


def patch(text):
    if SENTINEL in text:
        return text
    count = text.count(ANCHOR)
    if count != 1:
        raise RuntimeError(
            f"GuidePopup Bar-section anchor: expected one match, found {count}"
        )
    return text.replace(ANCHOR, ANCHOR + UPS_TAB, 1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("path", type=Path)
    args = parser.parse_args()
    args.path.write_text(patch(args.path.read_text(encoding="utf-8")), encoding="utf-8")


if __name__ == "__main__":
    main()
