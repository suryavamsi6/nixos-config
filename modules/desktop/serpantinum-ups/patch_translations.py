#!/usr/bin/env python3
"""Add the UPS label to Serpantinum's English Settings translations."""

import json
import sys
from pathlib import Path


path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
guide = data.setdefault("guide", {})
tabs = guide.setdefault("tabs", {})
tabs["ups"] = "UPS"
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
