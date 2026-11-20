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
PREVIEW_RES = ROOT / "tool/preview_res"

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
        self.assertEqual([child.tag for child in vector.getroot()], ["group"])
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
        self.assertIsNone(ET.fromstring(svg).find("{*}circle"))
        self.assertEqual(list(res.rglob("*ic_launcher_preview*")), [])

    def test_preview_layers_keep_the_formal_strokes_and_add_the_scheme_c_badge(self):
        formal = ET.parse(MAIN_ANDROID / "res/drawable/ic_launcher_foreground.xml").find("group")
        for layer, fill, color in (
            ("foreground", "#FFFFFFFF", "#FFB3202A"),
            ("monochrome", "#00000000", "#FFFFFFFF"),
        ):
            with self.subTest(layer=layer):
                vector = ET.parse(PREVIEW_RES / f"drawable/ic_launcher_preview_{layer}.xml").getroot()
                self.assertEqual([child.tag for child in vector], ["group", "path", "group"])
                strokes, circle, letter = vector
                self.assertEqual(strokes.attrib, formal.attrib)
                white_paths = strokes.findall("path")
                self.assertEqual(len(white_paths), 10)
                self.assertEqual([path.attrib for path in white_paths], [path.attrib for path in formal])
                self.assertEqual(circle.get(ANDROID + "pathData"),
                                 "M71.4,78.6 A7.2,7.2 0 1 1 85.8,78.6 A7.2,7.2 0 1 1 71.4,78.6 Z")
                self.assertEqual(circle.get(ANDROID + "fillColor"), fill)
                self.assertEqual(circle.get(ANDROID + "strokeColor"),
                                 "#FFFFFFFF" if layer == "monochrome" else None)
                self.assertEqual(circle.get(ANDROID + "strokeWidth"),
                                 "1.6" if layer == "monochrome" else None)
                self.assertEqual(letter.attrib, {
                    ANDROID + name: value for name, value in {
                        "pivotX": "10", "pivotY": "13.5", "scaleX": "0.2727", "scaleY": "0.2727",
                        "translateX": "68.6", "translateY": "65.4",
                    }.items()
                })
                self.assertEqual([path.get(ANDROID + "pathData") for path in letter], [
                    "M0,0 L0,27", "M0,10 A10,10 0 1 1 20,10 A10,10 0 1 1 0,10",
                ])
                for path in letter:
                    self.assertEqual(path.get(ANDROID + "strokeColor"), color)
                    self.assertEqual(path.get(ANDROID + "strokeWidth"), "6.8")
                    self.assertEqual(path.get(ANDROID + "strokeLineCap"), "round")
                    self.assertEqual(path.get(ANDROID + "strokeLineJoin"), "round")

    def test_preview_adaptive_icon_and_design_source(self):
        adaptive = ET.parse(PREVIEW_RES / "mipmap-anydpi-v26/ic_launcher_preview.xml").getroot()
        self.assertEqual({child.tag: child.get(ANDROID + "drawable") for child in adaptive}, {
            "background": "@drawable/ic_launcher_background",
            "foreground": "@drawable/ic_launcher_preview_foreground",
            "monochrome": "@drawable/ic_launcher_preview_monochrome",
        })
        self.assertEqual(list(PREVIEW_RES.rglob("*.png")), [])
        self.assertEqual((ROOT / "brand/chhers-preview-icon.svg").read_text(), launcher_icon.preview_svg())

    def test_preview_init_script_uses_separate_resources_label_and_icon(self):
        manifest = (MAIN_ANDROID / "AndroidManifest.xml").read_text()
        formal = ET.fromstring(manifest).find("application")
        self.assertEqual(formal.get(ANDROID + "label"), "Chhers")
        self.assertEqual(formal.get(ANDROID + "icon"), "@mipmap/ic_launcher")
        script = build_preview.preview_init_script()
        self.assertIn(f"project.projectDir.canonicalPath == '{ROOT / 'android/app'}'", script)
        self.assertIn(f"def previewRes = project.file('{PREVIEW_RES}')", script)
        self.assertIn("project.android.sourceSets.main.res.srcDir(previewRes)", script)
        self.assertIn("project.android.sourceSets.main.manifest.srcFile(previewManifest)", script)
        self.assertIn("previewManifest.setText(manifest, 'UTF-8')", script)
        replacements = re.findall(
            r"\.replace\(\s*'(android:(?:label|icon)=\"[^\"]+\")',\s*'(android:(?:label|icon)=\"[^\"]+\")'\)",
            script,
        )
        for original, substitute in replacements:
            self.assertIn(original, manifest)
            manifest = manifest.replace(original, substitute)
        preview = ET.fromstring(manifest).find("application")
        self.assertEqual(build_preview.LABEL, "chhers-preview")
        self.assertEqual(preview.get(ANDROID + "label"), build_preview.LABEL)
        self.assertEqual(preview.get(ANDROID + "icon"), "@mipmap/ic_launcher_preview")
        self.assertEqual(build_preview.PACKAGE, "com.chhreader.chh_app.preview")
        self.assertIn(f"applicationId = '{build_preview.PACKAGE}'", script)
        for formal_config in ("android/app/build.gradle.kts", "tool/build_release.sh"):
            self.assertNotIn("preview_res", (ROOT / formal_config).read_text())

    def test_badging_must_point_to_the_preview_icon_even_with_optimized_paths(self):
        resources = (
            "    resource 0x7f0d0000 mipmap/ic_launcher\n"
            "      (anydpi) (file) res/BW.xml type=XML\n"
            "    resource 0x7f0d0001 mipmap/ic_launcher_preview\n"
            "      (anydpi) (file) res/BX.xml type=XML\n"
        )
        preview_icon = "application-icon-160:'res/BX.xml'\n"
        formal_icon = "application-icon-240:'res/BW.xml'\n"
        build_preview.verify_launcher_icon(preview_icon, resources)
        for badging, table in (
            (formal_icon, resources), (preview_icon + formal_icon, resources), ("", resources),
            (preview_icon, resources.replace("mipmap/ic_launcher_preview", "drawable/ic_launcher_preview")),
        ):
            with self.subTest(badging=badging, resources=table), self.assertRaisesRegex(
                SystemExit, "mipmap/ic_launcher_preview"
            ):
                build_preview.verify_launcher_icon(badging, table)

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
