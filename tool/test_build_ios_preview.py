import importlib.util
from pathlib import Path
import plistlib
import subprocess
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import call, patch

spec = importlib.util.spec_from_file_location(
    'build_ios_preview', Path(__file__).with_name('build_ios_preview.py'),
)
preview = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preview)


class PreviewVersionTest(unittest.TestCase):
    def test_version_code(self):
        self.assertEqual(preview.version_code('90.0.1'), 900001)
        self.assertEqual(preview.version_code('90.3.12'), 900312)
        self.assertEqual(preview.version_code('90.99.99'), 909999)

    def test_rejects_invalid_versions(self):
        for version in (
            '', '1.0.17', '90.0', '90.0.0', '90.00.1', '90.1.01',
            '90.100.1', '90.0.100', '90.0.1+900001', '90.0.1 ',
        ):
            with self.subTest(version=version), self.assertRaises(ValueError):
                preview.version_code(version)


class PreviewPlistTest(unittest.TestCase):
    def setUp(self):
        directory = TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.path = Path(directory.name) / 'Info.plist'
        self.original = plistlib.dumps({
            'CFBundleDisplayName': 'Chhers',
            'CFBundleIdentifier': '$(PRODUCT_BUNDLE_IDENTIFIER)',
            'CFBundleVersion': '$(FLUTTER_BUILD_NUMBER)',
        }, fmt=plistlib.FMT_BINARY)
        self.path.write_bytes(self.original)
        replace = patch.object(
            preview.subprocess, 'run', side_effect=self.fake_plutil,
        )
        self.replace = replace.start()
        self.addCleanup(replace.stop)

    def fake_plutil(self, command, *, check):
        _, _, key, _, value, path = command
        file = Path(path)
        info = plistlib.loads(file.read_bytes())
        info[key] = value
        file.write_bytes(plistlib.dumps(info))

    def test_patches_both_keys_then_restores_exact_bytes(self):
        with preview.preview_plist(self.path):
            self.assertEqual(plistlib.loads(self.path.read_bytes()), {
                'CFBundleDisplayName': preview.LABEL,
                'CFBundleIdentifier': preview.PACKAGE,
                'CFBundleVersion': '$(FLUTTER_BUILD_NUMBER)',
            })
        self.assertEqual(self.replace.call_args_list, [
            call(
                ['plutil', '-replace', 'CFBundleDisplayName', '-string',
                 preview.LABEL, str(self.path)],
                check=True,
            ),
            call(
                ['plutil', '-replace', 'CFBundleIdentifier', '-string',
                 preview.PACKAGE, str(self.path)],
                check=True,
            ),
        ])
        self.assertEqual(self.path.read_bytes(), self.original)

    def test_restores_on_build_failure(self):
        with self.assertRaises(subprocess.CalledProcessError):
            with preview.preview_plist(self.path):
                raise subprocess.CalledProcessError(1, 'flutter')
        self.assertEqual(self.path.read_bytes(), self.original)

    def test_restores_on_partial_patch_failure(self):
        def fail_second_replace(command, *, check):
            if command[2] == 'CFBundleIdentifier':
                raise subprocess.CalledProcessError(1, command)
            self.fake_plutil(command, check=check)

        self.replace.side_effect = fail_second_replace
        with self.assertRaises(subprocess.CalledProcessError):
            with preview.preview_plist(self.path):
                self.fail('构建不应在 plist 修改失败后继续')
        self.assertEqual(self.path.read_bytes(), self.original)


if __name__ == '__main__':
    unittest.main()
