#!/usr/bin/env python3
"""Render a Ghostty palette from Serpantinum's Matugen color cache."""

import json
import os
import sys
import tempfile
from pathlib import Path


DEFAULTS = {
    "base": "#1e1e2e",
    "crust": "#11111b",
    "surface2": "#585b70",
    "text": "#cdd6f4",
    "overlay0": "#6c7086",
    "red": "#f38ba8",
    "green": "#a6e3a1",
    "yellow": "#f9e2af",
    "blue": "#89b4fa",
    "mauve": "#cba6f7",
    "teal": "#94e2d5",
    "peach": "#fab387",
}


def colors_from(path: Path) -> dict[str, str]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        data = data.get("colors", data)
        if not isinstance(data, dict):
            raise ValueError("Matugen color data is not an object")
    except (OSError, ValueError, json.JSONDecodeError):
        data = {}

    return {name: str(data.get(name, fallback)) for name, fallback in DEFAULTS.items()}


def render_ghostty(colors: dict[str, str]) -> str:
    # ANSI colors use Matugen semantic roles so terminal output follows the
    # same palette as Serpantinum and the existing Kitty/Cava integrations.
    palette = [
        colors["crust"],
        colors["red"],
        colors["green"],
        colors["yellow"],
        colors["blue"],
        colors["mauve"],
        colors["teal"],
        colors["text"],
        colors["overlay0"],
        colors["red"],
        colors["green"],
        colors["yellow"],
        colors["blue"],
        colors["mauve"],
        colors["teal"],
        colors["text"],
    ]

    lines = [
        "# Generated from Serpantinum Matugen colors; do not edit.",
        f"background = {colors['base']}",
        f"foreground = {colors['text']}",
        f"cursor-color = {colors['text']}",
        f"selection-background = {colors['surface2']}",
        f"selection-foreground = {colors['text']}",
    ]
    lines.extend(f"palette = {index}={color}" for index, color in enumerate(palette))
    return "\n".join(lines) + "\n"


def render_starship(source: Path, colors: dict[str, str]) -> str:
    try:
        content = source.read_text(encoding="utf-8")
    except OSError:
        content = ""
    lines = content.splitlines()
    palette_line = 'palette = "matugen"'
    replaced = False
    output = []
    for line in lines:
        if line.lstrip().startswith("palette =") and not line.lstrip().startswith("[palette"):
            output.append(palette_line)
            replaced = True
        else:
            output.append(line)
    if not replaced:
        output.insert(0, palette_line)
    if any(line.strip() == "[palettes.matugen]" for line in output):
        return "\n".join(output).rstrip() + "\n"
    palette = {
        "base": colors["base"],
        "crust": colors["crust"],
        "text": colors["text"],
        "red": colors["red"],
        "green": colors["green"],
        "yellow": colors["yellow"],
        "blue": colors["blue"],
        "sapphire": colors["blue"],
        "teal": colors["teal"],
        "peach": colors["peach"],
        "mauve": colors["mauve"],
        "lavender": colors["blue"],
    }
    output.extend(["", "[palettes.matugen]"])
    output.extend(f"{name} = \"{value}\"" for name, value in palette.items())
    return "\n".join(output).rstrip() + "\n"


def write_atomic(destination: Path, content: str) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", dir=destination.parent, delete=False
    ) as temporary:
        temporary.write(content)
        temporary_path = Path(temporary.name)
    temporary_path.replace(destination)


def main() -> int:
    if len(sys.argv) not in (3, 5):
        print(
            f"usage: {sys.argv[0]} MATUGEN_JSON GHOSTTY_CONFIG "
            "[STARSHIP_SOURCE STARSHIP_CONFIG]",
            file=sys.stderr,
        )
        return 2

    source = Path(os.path.expanduser(sys.argv[1]))
    colors = colors_from(source)
    write_atomic(Path(os.path.expanduser(sys.argv[2])), render_ghostty(colors))
    if len(sys.argv) == 5:
        write_atomic(
            Path(os.path.expanduser(sys.argv[4])),
            render_starship(Path(os.path.expanduser(sys.argv[3])), colors),
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
