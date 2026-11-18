import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('update_build_config', ROOT / 'tool/update_build_config.py')
config = importlib.util.module_from_spec(spec)
spec.loader.exec_module(config)


class UpdateBuildConfigTest(unittest.TestCase):
    def test_invalid_and_disabled_config(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'private.json'
            for value in [[], {}, {'CHH_UPDATE_ENDPOINTS': 3},
                          {'CHH_UPDATE_ENDPOINTS': 'https://user:password@example.invalid'},
                          {'CHH_UPDATE_ENDPOINTS': 'https://example.invalid/path'},
                          {'CHH_UPDATE_ENDPOINTS': 'https://example.invalid:99999'},
                          {'CHH_UPDATE_ENDPOINTS': 'https://example.invalid,ftp://bad.invalid'},
                          {'CHH_UPDATE_ENDPOINTS': 'https://example.invalid', 'app_version': '99'}]:
                path.write_text(json.dumps(value))
                with self.assertRaises(ValueError):
                    config.validate(path)
            for value in ['', 'https://example.invalid', 'http://[::1]:8080,https://other.invalid/']:
                path.write_text(json.dumps({'CHH_UPDATE_ENDPOINTS': value}))
                config.validate(path)

    def test_release_script_only_reads_local_validated_configuration(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for folder in ['tool', 'android', 'config', 'bin', 'sdk/build-tools/36']:
                (root / folder).mkdir(parents=True)
            for filename in ['build_release.sh', 'update_build_config.py']:
                shutil.copy2(ROOT / 'tool' / filename, root / 'tool' / filename)
            (root / 'android/key.properties').write_text('fixture only')
            record = root / 'called.json'
            flutter = root / 'bin/flutter'
            flutter.write_text('#!/usr/bin/env python3\nimport json,sys\nfrom pathlib import Path\nPath("called.json").write_text(json.dumps(sys.argv[1:]))\np=Path("build/app/outputs/flutter-apk/app-release.apk");p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(b"fixture")\n')
            flutter.chmod(0o755)
            aapt = root / 'sdk/build-tools/36/aapt2'
            aapt.write_text('#!/bin/sh\nprintf "package: name=\x27com.example.fixture\x27 versionCode=\x2710013\x27\\nnative-code: \x27arm64-v8a\x27 \x27armeabi-v7a\x27 \x27x86_64\x27\\n"\n')
            aapt.chmod(0o755)
            env = {**os.environ, 'PATH': str(root / 'bin') + os.pathsep + os.environ['PATH'], 'ANDROID_HOME': str(root / 'sdk'), 'CHH_UPDATE_ENDPOINTS': 'https://legacy.invalid'}
            def run():
                return subprocess.run(['bash', 'tool/build_release.sh', '1.0.13'], cwd=root, env=env, capture_output=True, text=True)
            self.assertEqual(run().returncode, 0)
            self.assertFalse(any('UPDATE' in arg or 'define-from-file' in arg for arg in json.loads(record.read_text())))
            local = root / 'config/update.local.json'
            local.write_text(json.dumps({'CHH_UPDATE_ENDPOINTS': 'https://private.invalid'}))
            self.assertEqual(run().returncode, 0)
            args = json.loads(record.read_text())
            self.assertIn('--dart-define-from-file=config/update.local.json', args)
            self.assertFalse(any('private.invalid' in arg for arg in args))
            record.unlink()
            local.write_text('{"CHH_UPDATE_ENDPOINTS":"http://user:secret@private.invalid"}')
            failed = run()
            self.assertNotEqual(failed.returncode, 0)
            self.assertFalse(record.exists())
            self.assertNotIn('secret', failed.stdout + failed.stderr)
            self.assertNotIn('private.invalid', failed.stdout + failed.stderr)


if __name__ == '__main__':
    unittest.main()
