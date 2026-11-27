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
                self.assertEqual(config.validate(path), value)


class ReleaseBuildConfigTest(unittest.TestCase):
    ENDPOINTS = 'https://fixture-update.invalid,http://fixture-fallback.invalid:8080'
    VOICE = {
        'CHH_VOICE_APP_ID': '81234056789',
        'CHH_VOICE_SECRET_ID': 'fixture-secret-id',
        'CHH_VOICE_SECRET_KEY': 'fixture-secret-key',
        'CHH_VOICE_ENGINE': 'fixture_engine.2',
    }

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        root = self.root = Path(tmp.name)
        for folder in ['tool', 'android', 'config', 'bin', 'sdk/build-tools/36']:
            (root / folder).mkdir(parents=True)
        for filename in ['build_release.sh', 'update_build_config.py', 'voice_build_config.py']:
            shutil.copy2(ROOT / 'tool' / filename, root / 'tool' / filename)
        (root / 'android/key.properties').write_text('fixture only')
        self.record = root / 'called.json'
        self.update = root / 'config/update.local.json'
        self.voice = root / 'config/voice.local.json'
        flutter = root / 'bin/flutter'
        flutter.write_text(
            '#!/usr/bin/env python3\n'
            'import json, sys\n'
            'from pathlib import Path\n'
            'Path("called.json").write_text(json.dumps(sys.argv[1:]))\n'
            'apk = Path("build/app/outputs/flutter-apk/app-release.apk")\n'
            'apk.parent.mkdir(parents=True, exist_ok=True)\n'
            'apk.write_bytes(b"fixture")\n'
        )
        flutter.chmod(0o755)
        aapt = root / 'sdk/build-tools/36/aapt2'
        aapt.write_text(
            '#!/bin/sh\n'
            'printf "package: name=\x27com.example.fixture\x27 versionCode=\x2710013\x27\\n'
            'native-code: \x27arm64-v8a\x27 \x27armeabi-v7a\x27 \x27x86_64\x27\\n"\n'
        )
        aapt.chmod(0o755)
        self.env = {
            **os.environ,
            'PATH': str(root / 'bin') + os.pathsep + os.environ['PATH'],
            'ANDROID_HOME': str(root / 'sdk'),
            'CHH_UPDATE_ENDPOINTS': 'https://legacy.invalid',
        }

    def run_release(self, *private_values):
        self.record.unlink(missing_ok=True)
        result = subprocess.run(
            ['bash', 'tool/build_release.sh', '1.0.13'], cwd=self.root,
            env=self.env, capture_output=True, text=True,
        )
        captured = result.stdout + result.stderr
        if self.record.exists():
            captured += self.record.read_text()
        for value in (*self.VOICE.values(), *self.ENDPOINTS.split(','),
                      'legacy.invalid', *private_values):
            self.assertNotIn(value, captured)
        return result

    def assert_defines(self, source, *files):
        result = self.run_release()
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = [line for line in result.stdout.splitlines() if line.startswith('语音：')]
        self.assertEqual(lines, [f'语音：{source}'])
        args = json.loads(self.record.read_text())
        self.assertFalse(any(arg.startswith('--dart-define=CHH_') for arg in args))
        config_args = [arg for arg in args if arg.startswith('--dart-define-from-file=')]
        self.assertEqual(config_args, [f'--dart-define-from-file=config/{file}' for file in files])

    def assert_rejected(self, message, *private_values):
        result = self.run_release(*private_values)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, '')
        self.assertEqual(result.stderr.strip(), message)
        self.assertFalse(self.record.exists())

    def test_release_script_only_reads_local_validated_configuration(self):
        self.assert_defines('未配置')
        self.update.write_text(json.dumps({'CHH_UPDATE_ENDPOINTS': self.ENDPOINTS}))
        self.assert_defines('服务器签发', 'update.local.json')
        endpoint = 'http://fixture-user:fixture-password@fixture-invalid.invalid'
        self.update.write_text(json.dumps({'CHH_UPDATE_ENDPOINTS': endpoint}))
        self.assert_rejected(config.INVALID_CONFIG, 'fixture-user', 'fixture-password',
                             'fixture-invalid.invalid')

    def test_release_disabled_voice_is_not_injected(self):
        values = dict.fromkeys(self.VOICE, '')
        values['CHH_VOICE_ENGINE'] = self.VOICE['CHH_VOICE_ENGINE']
        self.voice.write_text(json.dumps(values))
        self.assert_defines('未配置')
        self.update.write_text(json.dumps({'CHH_UPDATE_ENDPOINTS': self.ENDPOINTS}))
        self.assert_defines('服务器签发', 'update.local.json')

    def test_release_injects_enabled_voice_and_accepts_empty_update_addresses(self):
        self.voice.write_text(json.dumps(self.VOICE))
        self.assert_defines('本机密钥', 'voice.local.json')
        self.update.write_text(json.dumps({'CHH_UPDATE_ENDPOINTS': ''}))
        self.assert_defines('本机密钥', 'update.local.json', 'voice.local.json')

    def test_release_rejects_partial_or_invalid_voice_before_flutter(self):
        for overrides in [
            {'CHH_VOICE_SECRET_KEY': ''},
            {'CHH_VOICE_SECRET_KEY': 'invalid-fixture/key'},
        ]:
            with self.subTest(overrides=overrides):
                self.voice.write_text(json.dumps({**self.VOICE, **overrides}))
                self.assert_rejected('语音配置无效，请检查本地配置文件。',
                                     'invalid-fixture/key')

    def test_release_rejects_update_and_local_voice_conflict_before_flutter(self):
        self.voice.write_text(json.dumps(self.VOICE))
        self.update.write_text(json.dumps({'CHH_UPDATE_ENDPOINTS': self.ENDPOINTS}))
        self.assert_rejected('更新服务已配置，不能同时内置语音密钥。')


if __name__ == '__main__':
    unittest.main()
