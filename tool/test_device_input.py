import contextlib
import io
import subprocess
import unittest
from unittest.mock import Mock

from device_input import DeviceInputError, InputRejected, main, send_input, validated_input


PACKAGE = 'com.chhreader.chh_app.preview'
ACTIVITY = f'    topResumedActivity=ActivityRecord{{abc u0 {PACKAGE}/.MainActivity t1}}\n'
WINDOW = f'  mCurrentFocus=Window{{abc u0 {PACKAGE}/.MainActivity}}\n'


def result(stdout='', stderr='', code=0):
    return subprocess.CompletedProcess([], code, stdout=stdout, stderr=stderr)


class DeviceInputTests(unittest.TestCase):
    def test_text_and_all_character_keys_are_rejected_before_adb(self):
        inputs = [['text', 'QA'], ['text', '装机']]
        inputs += [['keyevent', str(code)] for code in range(29, 55)]
        inputs += [['keyevent', prefix + chr(code)]
                   for code in range(ord('A'), ord('Z') + 1)
                   for prefix in ('', 'KEYCODE_')]
        inputs += [['keyevent', key] for key in
                   ('62', 'SPACE', 'KEYCODE_SPACE', '66', 'ENTER', 'KEYCODE_ENTER')]
        for arguments in inputs:
            with self.subTest(arguments=arguments):
                runner = Mock()
                with self.assertRaises(InputRejected):
                    send_input('test-device', PACKAGE, arguments, runner=runner)
                runner.assert_not_called()

    def test_only_home_and_back_navigation_keys_are_allowed(self):
        for key, code in [('3', '3'), ('HOME', '3'), ('KEYCODE_HOME', '3'),
                          ('4', '4'), ('BACK', '4'), ('KEYCODE_BACK', '4')]:
            with self.subTest(key=key):
                self.assertEqual(validated_input(['keyevent', key]), ['keyevent', code])

    def test_touch_commands_are_forwarded_after_both_guards(self):
        for arguments in [('tap', '10', '20'), ('swipe', '1', '2', '3', '4'),
                          ('swipe', '1', '2', '3', '4', '450'), ('keyevent', 'BACK')]:
            with self.subTest(arguments=arguments):
                runner = Mock(side_effect=[result(ACTIVITY), result(WINDOW), result()])
                send_input('test-device', PACKAGE, arguments, runner=runner)
                commands = [call.args[0] for call in runner.call_args_list]
                self.assertEqual(commands[0][-4:], ['shell', 'dumpsys', 'activity', 'activities'])
                self.assertEqual(commands[1][-3:], ['shell', 'dumpsys', 'window'])
                self.assertEqual(commands[2], ['adb', '-s', 'test-device', 'shell',
                                               'input', *validated_input(arguments)])

    def test_malformed_commands_and_input_bypasses_are_rejected(self):
        for arguments in [[], ['tap', '-1', '2'], ['tap', '1.5', '2'],
                          ['tap', '1', '2', 'text', 'QA'], ['swipe', '1', '2'],
                          ['swipe', '1', '2', '3', '4', '0'],
                          ['swipe', '1', '2', '3', '4', '10001'],
                          ['keyevent', '--longpress', '4'],
                          ['keycombination', '113', '29'], ['keyboard', 'text', 'QA']]:
            with self.subTest(arguments=arguments), self.assertRaises(InputRejected):
                validated_input(arguments)

    def test_activity_foreground_loss_never_sends_input(self):
        for activity in ['', ACTIVITY.replace(PACKAGE, 'com.tencent.mm'),
                         ACTIVITY.replace(PACKAGE, 'prefix.' + PACKAGE)]:
            with self.subTest(activity=activity):
                runner = Mock(return_value=result(activity))
                with self.assertRaisesRegex(DeviceInputError, '不在前台'):
                    send_input('test-device', PACKAGE, ['tap', '10', '20'], runner=runner)
                self.assertEqual(runner.call_count, 1)

    def test_legacy_activity_dumps_are_recognized(self):
        record = f'ActivityRecord{{abc u0 {PACKAGE}/com.chhreader.chh_app.MainActivity t10}}'
        # Android 10没有topResumedActivity；Android 7–9另有mFocusedActivity
        android10 = f'    mResumedActivity: {record}\n ResumedActivity:{record}\n'
        android7 = f'  mFocusedActivity: {record}\n    mResumedActivity: {record}\n'
        for dump in [android10, android7]:
            with self.subTest(dump=dump):
                runner = Mock(side_effect=[result(dump), result(WINDOW), result()])
                send_input('test-device', PACKAGE, ['tap', '10', '20'], runner=runner)
                self.assertEqual(runner.call_count, 3)
            with self.subTest(dump=dump, other=True):
                runner = Mock(return_value=result(dump.replace(PACKAGE, 'com.tencent.mm')))
                with self.assertRaisesRegex(DeviceInputError, '不在前台'):
                    send_input('test-device', PACKAGE, ['tap', '10', '20'], runner=runner)
                self.assertEqual(runner.call_count, 1)

    def test_newest_activity_field_wins_over_legacy_lines(self):
        stale = f'    mResumedActivity: ActivityRecord{{abc u0 {PACKAGE}/.MainActivity t1}}\n'
        dump = stale + ACTIVITY.replace(PACKAGE, 'com.tencent.mm')
        runner = Mock(return_value=result(dump))
        with self.assertRaisesRegex(DeviceInputError, '不在前台'):
            send_input('test-device', PACKAGE, ['tap', '10', '20'], runner=runner)
        self.assertEqual(runner.call_count, 1)

    def test_window_focus_loss_never_sends_input(self):
        for window in ['', '  mCurrentFocus=null\n', WINDOW.replace(PACKAGE, 'com.android.systemui')]:
            with self.subTest(window=window):
                runner = Mock(side_effect=[result(ACTIVITY), result(window)])
                with self.assertRaisesRegex(DeviceInputError, '窗口焦点'):
                    send_input('test-device', PACKAGE, ['tap', '10', '20'], runner=runner)
                self.assertEqual(runner.call_count, 2)

    def test_device_error_stops_without_input_or_recovery(self):
        runner = Mock(return_value=result(stderr="error: device 'test-device' not found", code=1))
        with self.assertRaisesRegex(DeviceInputError, 'not found'):
            send_input('test-device', PACKAGE, ['tap', '10', '20'], runner=runner)
        self.assertEqual(runner.call_count, 1)

    def test_window_query_error_stops_without_input(self):
        runner = Mock(side_effect=[result(ACTIVITY), result(stderr='error: device offline', code=1)])
        with self.assertRaisesRegex(DeviceInputError, 'offline'):
            send_input('test-device', PACKAGE, ['tap', '10', '20'], runner=runner)
        self.assertEqual(runner.call_count, 2)
        self.assertFalse(any(call.args[0][3:5] == ['shell', 'input']
                             for call in runner.call_args_list))

    def test_timeout_stops_without_input(self):
        runner = Mock(side_effect=subprocess.TimeoutExpired('adb', 15))
        with self.assertRaisesRegex(DeviceInputError, '超时'):
            send_input('test-device', PACKAGE, ['tap', '10', '20'], runner=runner)
        self.assertEqual(runner.call_count, 1)

    def test_cli_rejects_hardware_input_without_contacting_device(self):
        runner = Mock()
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as error:
            main(['--device', 'test-device', '--package', PACKAGE,
                  'input', 'text', 'QA'], runner=runner)
        self.assertEqual(error.exception.code, 2)
        runner.assert_not_called()

    def test_cli_accepts_explicit_device_package_and_input(self):
        runner = Mock(side_effect=[result(ACTIVITY), result(WINDOW), result()])
        self.assertEqual(main(['--device', 'test-device', '--package', PACKAGE,
                               'input', 'tap', '10', '20'], runner=runner), 0)

    def test_cli_device_error_returns_failure_without_traceback_or_recovery(self):
        runner = Mock(return_value=result(stderr='error: device offline', code=1))
        errors = io.StringIO()
        with contextlib.redirect_stderr(errors):
            code = main(['--device', 'test-device', '--package', PACKAGE,
                         'input', 'tap', '10', '20'], runner=runner)
        self.assertEqual(code, 1)
        self.assertIn('offline', errors.getvalue())
        self.assertNotIn('Traceback', errors.getvalue())
        self.assertEqual(runner.call_count, 1)


if __name__ == '__main__':
    unittest.main()
