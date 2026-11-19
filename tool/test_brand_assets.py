"""Check the generated icon and preview manifest without building an APK."""
from pathlib import Path
import re
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

import build_preview
import launcher_icon

ROOT = Path(__file__).resolve().parent.parent
ANDROID = "{http://schemas.android.com/apk/res/android}"
MAIN_ANDROID = ROOT / "android/app/src/main"

# R2b-Chh-ers-light.svg with its positions translated by (15.78, 31.3).
R2B_PATHS = [
    "M38.83,47.35 A13.5,13.5 0 1 1 38.83,28.25",
    "M50.23,24.3 L50.23,51.3",
    "M50.23,38.5 A7.2,7.2 0 0 1 64.63,38.5 M64.63,38.5 L64.63,51.3",
    "M77.83,24.3 L77.83,51.3",
    "M77.83,38.5 A7.2,7.2 0 0 1 92.23,38.5 M92.23,38.5 L92.23,51.3",
    "M37.49,80.13 A10,10 0 1 1 39.83,73.7",
    "M19.83,73.7 L39.83,73.7",
    "M50.23,63.7 L50.23,83.7",
    "M50.23,71.98 A8.28,8.28 0 0 1 58.51,63.7 M58.51,63.7 L60.61,63.7",
    (
        "M82.31,65.9 C81.31,64.4 79.41,63.7 77.21,63.7 "
        "C73.61,63.7 71.01,65.8 71.01,68.7 C71.01,72.1 74.41,72.9 77.41,73.6 "
        "C80.61,74.3 83.81,75.2 83.81,78.6 C83.81,81.7 81.01,83.7 77.21,83.7 "
        "C74.61,83.7 72.21,82.7 70.81,80.9"
    ),
]


class BrandAssetsTest(unittest.TestCase):
    def test_launcher_uses_r2b_strokes_and_reuses_them_for_themed_icon(self):
        res = MAIN_ANDROID / "res"
        vector = ET.parse(res / "drawable/ic_launcher_foreground.xml")
        group = vector.find("group")
        self.assertEqual(group.get(ANDROID + "scaleX"), "0.58")
        self.assertEqual(group.get(ANDROID + "scaleY"), "0.58")
        self.assertEqual(group.get(ANDROID + "pivotX"), "54")
        self.assertEqual(group.get(ANDROID + "pivotY"), "54")
        paths = group.findall("path")
        self.assertEqual([path.get(ANDROID + "pathData") for path in paths], R2B_PATHS)
        for path in paths:
            self.assertEqual(path.get(ANDROID + "strokeWidth"), "6.8")
            self.assertEqual(path.get(ANDROID + "strokeLineCap"), "round")
            self.assertEqual(path.get(ANDROID + "strokeLineJoin"), "round")

        adaptive = ET.parse(res / "mipmap-anydpi-v26/ic_launcher.xml")
        for layer in ("foreground", "monochrome"):
            self.assertEqual(adaptive.find(layer).get(ANDROID + "drawable"),
                             "@drawable/ic_launcher_foreground")

        svg = (ROOT / "brand/chhers-icon.svg").read_text()
        self.assertEqual(svg, launcher_icon.svg())
        self.assertEqual([path.get("d") for path in ET.fromstring(svg).findall("{*}g/{*}path")],
                         R2B_PATHS)

    def test_preview_template_replaces_the_formal_label_with_the_delivery_label(self):
        manifest = (MAIN_ANDROID / "AndroidManifest.xml").read_text()
        formal = ET.fromstring(manifest).find("application")
        self.assertEqual(formal.get(ANDROID + "label"), "Chhers")
        template = (ROOT / "tool/preview_package.gradle").read_text()
        replacement = re.search(
            r"sourceManifest\.getText\('UTF-8'\)\.replace\(\s*"
            r"'(android:label=\"[^\"]+\")', '(android:label=\"[^\"]+\")'\)",
            template,
        )
        self.assertIsNotNone(replacement)
        original, substitute = replacement.groups()
        self.assertIn(original, manifest)
        preview = ET.fromstring(manifest.replace(original, substitute)).find("application")
        self.assertEqual(build_preview.LABEL, "chhers-preview")
        self.assertEqual(preview.get(ANDROID + "label"), build_preview.LABEL)
        self.assertEqual(build_preview.PACKAGE, "com.chhreader.chh_app.preview")
        self.assertIn(f"applicationId = '{build_preview.PACKAGE}'", template)

    def test_previous_preview_label_still_reserves_its_version(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            (repo / "pubspec.yaml").write_text("version: 1.0.14+10014\n")
            version = "90.1.9"
            out = repo / "build/preview" / version
            out.mkdir(parents=True)
            previous = out / f"chher-preview-{version}.apk"
            previous.touch()
            with patch.object(build_preview, "ROOT", repo), patch(
                "sys.argv", ["build_preview.py", version]
            ), self.assertRaisesRegex(SystemExit, re.escape(previous.name)):
                build_preview.main()


if __name__ == "__main__":
    unittest.main()
