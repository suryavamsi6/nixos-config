#!/usr/bin/env python3
"""Focused tests for the Serpantinum active-color bridge."""

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "matugen-ghostty.py"
spec = importlib.util.spec_from_file_location("bridge", SCRIPT)
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class ActiveColorsTest(unittest.TestCase):
    def test_matugen_colors_reach_ghostty_and_starship(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            active = root / "qs_matugen_colors.json"
            stale = root / "qs_colors.json"
            ghostty = root / "ghostty" / "matugen.conf"
            source = root / "starship.toml"
            starship = root / "starship-matugen.toml"
            source.write_text('palette = "catppuccin_macchiato"\n[character]\nsuccess_symbol = "ok"\n')
            stale.write_text(json.dumps({"base": "#999999"}))
            for data, expected in [
                ({"base": "#123456", "text": "#abcdef", "red": "#ff0000"}, "#123456"),
                ({"colors": {"base": "#654321", "text": "#fedcba", "red": "#00ff00"}}, "#654321"),
            ]:
                active.write_text(json.dumps(data))
                subprocess.run([sys.executable, str(SCRIPT), str(active), str(ghostty), str(source), str(starship)], check=True)
                ghost = ghostty.read_text()
                prompt = starship.read_text()
                self.assertIn(f"background = {expected}", ghost)
                self.assertIn(f'base = "{expected}"', prompt)
                self.assertIn('palette = "matugen"', prompt)
                self.assertIn('[character]', prompt)
                self.assertNotIn('#999999', ghost + prompt)
                self.assertIn(f"palette = 1={data.get('colors', data)['red']}", ghost)

    def test_missing_and_invalid_json_use_existing_defaults(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "colors.json"
            self.assertEqual(bridge.colors_from(path), bridge.DEFAULTS)
            path.write_text("{ incomplete")
            self.assertEqual(bridge.colors_from(path), bridge.DEFAULTS)
            path.write_text(json.dumps({"colors": {"base": "#aabbcc"}}))
            self.assertEqual(bridge.colors_from(path)["text"], bridge.DEFAULTS["text"])

    def test_cli_error_propagates_write_failure_and_validates_args(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            source.write_text("{}")
            result = subprocess.run([sys.executable, str(SCRIPT), str(source), str(root)], capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            result = subprocess.run([sys.executable, str(SCRIPT)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertIn("usage:", result.stderr)

    def test_nix_service_and_watcher_use_matugen_file(self):
        nix = (HERE / "default.nix").read_text()
        self.assertEqual(nix.count('${config.xdg.stateHome}/serpantinum/qs_matugen_colors.json'), 2)
        self.assertIn('PathChanged =', nix)


if __name__ == "__main__":
    unittest.main()
