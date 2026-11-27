from base64 import b64encode
from contextlib import redirect_stderr, redirect_stdout
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

if __package__:
    from . import build_preview as preview
else:
    import build_preview as preview

ENDPOINTS = 'https://fixture-voice.invalid, http://fixture-fallback.invalid:8080'
FAKE_BUILD = """
from base64 import b64encode
import json
from pathlib import Path
import stat
import sys

args = sys.argv[2:]
Path('called.json').write_text(json.dumps(args))
print('fixture build')
for arg in args:
    path = Path(arg.split('=', 1)[1])
    assert stat.S_IMODE(path.stat().st_mode) == 0o600
    endpoints = json.loads(Path('config/update.local.json').read_text())['CHH_UPDATE_ENDPOINTS']
    assert json.loads(path.read_text()) == {'CHH_VOICE_ENDPOINTS': endpoints}
    print(endpoints)
    print(endpoints.split(',')[1].strip(), file=sys.stderr)
    print(b64encode(f'CHH_VOICE_ENDPOINTS={endpoints}'.encode()).decode())
sys.exit(int(sys.argv[1]))
"""


class PreviewVoiceConfigTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        (self.root / 'config').mkdir()
        # A voice file that cannot be parsed must never affect the preview.
        (self.root / 'config/voice.local.json').write_text('fixture-invalid-voice')
        self.update = self.root / 'config/update.local.json'
        self.log = self.root / 'build.log'

    def run_fake_build(self, exit_code):
        command = [sys.executable, '-c', FAKE_BUILD, str(exit_code)]
        out = io.StringIO()
        with redirect_stdout(out), redirect_stderr(out):
            endpoints = preview.preview_voice_endpoints(self.root)
            if exit_code:
                with self.assertRaises(subprocess.CalledProcessError) as error:
                    preview.run_flutter_build(command, self.root, self.log, endpoints)
                self.assertEqual(error.exception.returncode, exit_code)
                self.assertNotIn(ENDPOINTS, str(error.exception))
            else:
                preview.run_flutter_build(command, self.root, self.log, endpoints)
        self.assertEqual(out.getvalue(), '')
        return json.loads((self.root / 'called.json').read_text())

    def test_missing_or_empty_update_config_does_not_inject_voice(self):
        self.assertEqual(self.run_fake_build(0), [])
        self.update.write_text(json.dumps({'CHH_UPDATE_ENDPOINTS': ''}))
        self.assertEqual(self.run_fake_build(0), [])
        self.assertEqual(self.log.read_text(), 'fixture build\n')

    def test_temporary_voice_only_config_is_private_and_cleaned_after_build(self):
        self.update.write_text(json.dumps({'CHH_UPDATE_ENDPOINTS': ENDPOINTS}))
        for exit_code in (0, 23):
            with self.subTest(exit_code=exit_code):
                args = self.run_fake_build(exit_code)
                self.assertEqual(len(args), 1)
                option, filename = args[0].split('=', 1)
                self.assertEqual(option, '--dart-define-from-file')
                self.assertFalse(Path(filename).exists())
                log = self.log.read_text()
                self.assertIn('fixture build', log)
                self.assertEqual(log.count('[redacted]'), 3)
                encoded = b64encode(f'CHH_VOICE_ENDPOINTS={ENDPOINTS}'.encode()).decode()
                for value in (*map(str.strip, ENDPOINTS.split(',')), encoded):
                    self.assertNotIn(value, log)
                    self.assertNotIn(value, args[0])

    def test_invalid_update_config_stops_before_build_with_release_message(self):
        self.update.write_text('{"CHH_UPDATE_ENDPOINTS":"http://user:fixture-password@bad.invalid"}')
        (self.root / 'pubspec.yaml').write_text('version: 1.0.1+10001\n')
        with patch.object(preview, 'ROOT', self.root), patch.object(
            sys, 'argv', ['build_preview.py', '90.0.1']
        ), patch.object(preview, 'run_flutter_build') as build:
            with self.assertRaises(SystemExit) as error:
                preview.main()
        self.assertEqual(str(error.exception), preview.update_build_config.INVALID_CONFIG)
        build.assert_not_called()
        self.assertFalse((self.root / 'build').exists())


if __name__ == '__main__':
    unittest.main()
