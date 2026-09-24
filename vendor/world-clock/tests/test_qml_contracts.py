from pathlib import Path
import unittest


ROOT = Path(__file__).parents[1]


class QmlContractTests(unittest.TestCase):
    def test_globe_uses_stable_canvas_renderer(self):
        source = (ROOT / "qml/worldclock/WorldClockGlobe.qml").read_text(encoding="utf-8")
        self.assertIn("Canvas {", source)
        self.assertIn("function projectCoordinate", source)
        self.assertIn("markerLayout", source)
        self.assertNotIn("import QtQuick3D", source)
        self.assertNotIn("View3D", source)
        self.assertNotIn("WorldClockGlobe3D", source)
        self.assertIn("readonly property var landmasses", source)
        self.assertIn("function drawLandmass", source)
        self.assertNotIn("earthTexture", source)

    def test_globe_draws_white_city_pointers(self):
        source = (ROOT / "qml/worldclock/WorldClockGlobe.qml").read_text(encoding="utf-8")
        self.assertIn('context.strokeStyle = selected ? "rgba(255,255,255,1)"', source)
        self.assertIn('context.fillStyle = "#ffffff"', source)
        self.assertIn("placement.pointX", source)
        self.assertIn("placement.anchorX", source)

    def test_bar_widget_debounces_popup_toggle(self):
        source = (ROOT / "qml/bar/modules/WorldClockWidget.qml").read_text(encoding="utf-8")
        self.assertIn("property bool togglePending: false", source)
        self.assertIn("id: toggleGuard", source)
        self.assertIn("enabled: !root.togglePending", source)

    def test_bar_icon_tracks_configured_cities(self):
        source = (ROOT / "qml/bar/modules/WorldClockWidget.qml").read_text(encoding="utf-8")
        self.assertIn("WorldClockService.cities", source)
        self.assertIn('context.fillStyle = "#07090d"', source)
        self.assertIn('context.strokeStyle = "#ffffff"', source)


if __name__ == "__main__":
    unittest.main()
