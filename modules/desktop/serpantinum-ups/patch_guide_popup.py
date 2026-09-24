#!/usr/bin/env python3
"""Add the UPS page to Serpantinum's Settings sidebar."""

import argparse
from pathlib import Path

SENTINEL = "UPS_SETTINGS_TAB_PATCH_V1"


def patch(text):
    if SENTINEL in text:
        return text
    lines = text.splitlines(keepends=True)
    for index, line in enumerate(lines):
        if 'id: "Bar", key: "bar", name: "Bar"' in line:
            lines[index:index] = [
                "        // UPS_SETTINGS_TAB_PATCH_V1\n",
                '        { id: "UPS", key: "ups", name: "UPS", icon: "󰁯", file: "UpsTab.qml" },\n',
            ]
            return "".join(lines)
    raise RuntimeError("GuidePopup sidebar anchor not found")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("path", type=Path)
    args = parser.parse_args()
    args.path.write_text(patch(args.path.read_text(encoding="utf-8")), encoding="utf-8")


if __name__ == "__main__":
    main()


