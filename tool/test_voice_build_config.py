import json
from pathlib import Path
import tempfile
import unittest

if __package__:
    from . import voice_build_config as config
else:
    import voice_build_config as config

ROOT = Path(__file__).resolve().parent.parent
EMPTY = dict.fromkeys((*config.CREDENTIALS, config.ENGINE), '')
VALID = dict(zip(EMPTY, ('81234056789', 'id._~-', 'key._~-', '16k_zh_en_2.0')))


class VoiceBuildConfigTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.path = Path(temp.name) / 'voice.local.json'

    def check(self, values):
        self.path.write_text(json.dumps(values))
        return config.validate(self.path)

    def assert_invalid(self, values):
        with self.assertRaises(ValueError) as error:
            self.check(values)
        self.assertEqual(str(error.exception), config.INVALID_CONFIG)

    def test_example_and_engine_only_config_are_disabled(self):
        example = ROOT / 'config/voice.example.json'
        self.assertEqual(json.loads(example.read_text()), EMPTY)
        self.assertFalse(config.validate(example))
        self.assertFalse(self.check({**EMPTY, config.ENGINE: '16k_zh_en_2.0'}))

    def test_complete_credentials_with_or_without_engine_are_enabled(self):
        self.assertTrue(self.check(VALID))
        self.assertTrue(self.check({**VALID, config.ENGINE: ''}))

    def test_rejects_wrong_keys_value_types_and_invalid_json(self):
        for value in [[], None, {}, {**VALID, 'fixture-extra': 'fixture-value'},
                      {key: VALID[key] for key in config.CREDENTIALS},
                      {**VALID, config.ENGINE: False},
                      {**VALID, config.CREDENTIALS[0]: 81234056789}]:
            with self.subTest(value=value):
                self.assert_invalid(value)
        self.path.write_text('{"CHH_VOICE_SECRET_KEY": "fixture-malformed",')
        with self.assertRaises(ValueError) as error:
            config.validate(self.path)
        self.assertEqual(str(error.exception), config.INVALID_CONFIG)
        self.assertIsNone(error.exception.__cause__)
        self.assertTrue(error.exception.__suppress_context__)

    def test_rejects_partial_credentials(self):
        for key in config.CREDENTIALS:
            with self.subTest(key=key):
                self.assert_invalid({**VALID, key: ''})
                self.assert_invalid({**EMPTY, key: VALID[key]})

    def test_rejects_invalid_characters_in_each_field(self):
        for key, value in zip(VALID, ('１２３', 'id/fixture', 'key=fixture', 'engine\n')):
            with self.subTest(key=key):
                self.assert_invalid({**VALID, key: value})

    def test_conflict_message_contains_no_configuration_values(self):
        self.path.write_text(json.dumps(VALID))
        update = self.path.with_name('update.local.json')
        endpoints = 'https://fixture-conflict.invalid'
        update.write_text(json.dumps({'CHH_UPDATE_ENDPOINTS': endpoints}))
        with self.assertRaises(ValueError) as error:
            config.release_source(self.path, update)
        message = str(error.exception)
        self.assertEqual(message, config.CONFLICT)
        for value in (*VALID.values(), endpoints):
            self.assertNotIn(value, message)


if __name__ == '__main__':
    unittest.main()
