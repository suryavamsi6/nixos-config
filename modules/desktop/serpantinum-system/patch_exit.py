#!/usr/bin/env python3
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


replace_once(
    """if command -v systemctl &>/dev/null; then
    systemctl --user stop graphical-session.target 2>/dev/null
    systemctl --user stop graphical-session-pre.target 2>/dev/null
fi

if command -v dinitctl &>/dev/null; then
    dinitctl --user stop graphical-session 2>/dev/null
fi

sleep 0.2

""",
    """# The compositor exit ends the graphical session. Stopping its target here
# would kill this detached script with Serpantinum before it can request exit.

""",
    "premature graphical-session stop",
)

replace_once(
    """    hyprctl dispatch 'hl.dsp.exit()' 2>/dev/null || \\
    pkill -SIGTERM -x Hyprland 2>/dev/null""",
    """    hyprctl dispatch 'hl.dsp.exit()' 2>/dev/null || \\
    hyprctl --instance 0 dispatch 'hl.dsp.exit()' 2>/dev/null || \\
    pkill -SIGTERM -x Hyprland 2>/dev/null""",
    "Hyprland instance fallback",
)

path.write_text(text)
