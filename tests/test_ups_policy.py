import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]
SCRIPT = ROOT / "modules/hardware/ups-policy.py"
SPEC = importlib.util.spec_from_file_location("ups_policy", SCRIPT)
UPS_POLICY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(UPS_POLICY)
GUIDE_PATCH = ROOT / "modules/desktop/serpantinum-ups/patch_guide_popup.py"
GUIDE_SPEC = importlib.util.spec_from_file_location("patch_guide_popup", GUIDE_PATCH)
GUIDE = importlib.util.module_from_spec(GUIDE_SPEC)
GUIDE_SPEC.loader.exec_module(GUIDE)

class UpsPolicyTests(unittest.TestCase):
    def policy_for(self, data):
        with tempfile.TemporaryDirectory() as directory:
            settings = Path(directory) / "settings.json"
            settings.write_text(json.dumps(data), encoding="utf-8")
            return UPS_POLICY.load_policy(settings)

    def test_defaults_when_settings_are_missing(self):
        self.assertEqual(
            UPS_POLICY.load_policy("/does/not/exist"),
            {"batteryLevel": 50, "minutes": 5},
        )

    def test_reads_serpantinum_ups_settings(self):
        self.assertEqual(
            self.policy_for(
                {"ups": {"shutdownBatteryLevel": 30, "shutdownMinutes": 10}}
            ),
            {"batteryLevel": 30, "minutes": 10},
        )

    def test_clamps_untrusted_values(self):
        self.assertEqual(
            self.policy_for(
                {"ups": {"shutdownBatteryLevel": 999, "shutdownMinutes": -5}}
            ),
            {"batteryLevel": 90, "minutes": 1},
        )

    def test_rejects_boolean_values(self):
        self.assertEqual(
            self.policy_for(
                {"ups": {"shutdownBatteryLevel": True, "shutdownMinutes": False}}
            ),
            {"batteryLevel": 50, "minutes": 5},
        )

    def test_rendered_config_is_local_usb_only(self):
        rendered = UPS_POLICY.render_config(
            {"batteryLevel": 30, "minutes": 10}, "/nix/store/scripts"
        )
        self.assertIn("UPSTYPE usb", rendered)
        self.assertIn("NISIP 127.0.0.1", rendered)
        self.assertIn("BATTERYLEVEL 30", rendered)
        self.assertIn("MINUTES 10", rendered)
        self.assertIn("SCRIPTDIR /nix/store/scripts", rendered)

    def test_settings_sidebar_patch_adds_one_ups_page(self):
        source = '{ id: "Bar", key: "bar", name: "Bar", icon: "󰹑", file: "BarTab.qml" },\n'
        patched = GUIDE.patch(source)
        self.assertIn('id: "UPS"', patched)
        self.assertEqual(patched.count('id: "UPS"'), 1)
        self.assertEqual(GUIDE.patch(patched), patched)

if __name__ == "__main__":
    unittest.main()
