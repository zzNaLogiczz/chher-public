#!/usr/bin/env python3
"""真机验收触摸入口；拒绝可能改变输入法模式的硬件文字/按键注入。"""

import argparse
import re
import subprocess
import sys


class InputRejected(ValueError):
    pass


class DeviceInputError(RuntimeError):
    pass


_NAVIGATION_KEYS = {
    '3': '3', 'HOME': '3', 'KEYCODE_HOME': '3',
    '4': '4', 'BACK': '4', 'KEYCODE_BACK': '4',
}
_PACKAGE = re.compile(r'(?:[A-Za-z_][A-Za-z0-9_]*\.)+[A-Za-z_][A-Za-z0-9_]*')


def validated_input(arguments):
    """在调用任何ADB命令之前限制输入类型，不提供硬件输入绕过开关。"""
    values = [str(value) for value in arguments]
    if not values:
        raise InputRejected('缺少输入动作；仅允许tap、swipe及Home/Back。')
    action, *parameters = values
    if action == 'keyevent':
        if len(parameters) != 1 or parameters[0].upper() not in _NAVIGATION_KEYS:
            raise InputRejected('仅允许Home/Back导航键；拒绝字符、Space、Enter等硬件按键。')
        return ['keyevent', _NAVIGATION_KEYS[parameters[0].upper()]]
    if action not in ('tap', 'swipe'):
        raise InputRejected('拒绝该输入动作；text等硬件输入可能改变输入法状态。')
    valid_count = len(parameters) == 2 if action == 'tap' else len(parameters) in (4, 5)
    if not valid_count or any(not re.fullmatch(r'[0-9]+', value) for value in parameters):
        raise InputRejected('tap需要两个非负整数坐标；swipe需要四个坐标及可选的正整数时长。')
    numbers = [int(value) for value in parameters]
    if action == 'swipe' and len(numbers) == 5 and not 1 <= numbers[4] <= 10000:
        raise InputRejected('swipe时长须为1–10000毫秒。')
    return [action, *(str(value) for value in numbers)]


def _adb(device, arguments, runner):
    try:
        result = runner(
            ['adb', '-s', device, *arguments],
            capture_output=True, text=True, timeout=15, check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise DeviceInputError(f'ADB不可用或超时，已停止：{error}') from error
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or '无错误详情').strip()[:400]
        raise DeviceInputError(f'ADB命令失败，已停止：{detail}')
    return result.stdout


def _belongs_to_package(line, package):
    return re.search(r'(?<![A-Za-z0-9_.])' + re.escape(package) + '/', line) is not None


# 前台Activity的字段名随系统版本变化：Android 11起为topResumedActivity；
# Android 10只有(m)ResumedActivity；Android 7–9另有mFocusedActivity。按新到旧取第一个出现的字段。
_RESUMED_MARKERS = ('topResumedActivity=', 'mFocusedActivity:', 'ResumedActivity:')


def _resumed_activity(dump):
    lines = dump.splitlines()
    for marker in _RESUMED_MARKERS:
        line = next((line for line in lines if marker in line), None)
        if line is not None:
            return line
    return ''


def send_input(device, package, arguments, *, runner=None):
    """只在目标Activity和窗口均处于前台时发送一个已校验动作。"""
    command = validated_input(arguments)
    if not device or device.startswith('-') or any(char.isspace() for char in device):
        raise InputRejected('设备标识无效。')
    if not _PACKAGE.fullmatch(package):
        raise InputRejected('包名无效。')
    runner = subprocess.run if runner is None else runner
    activities = _adb(device, ['shell', 'dumpsys', 'activity', 'activities'], runner)
    activity = _resumed_activity(activities)
    if not _belongs_to_package(activity, package):
        raise DeviceInputError('目标应用不在前台，已停止输入；不会自动拉回应用。')
    windows = _adb(device, ['shell', 'dumpsys', 'window'], runner)
    focus = next((line for line in windows.splitlines() if 'mCurrentFocus=' in line), '')
    if not _belongs_to_package(focus, package):
        raise DeviceInputError('窗口焦点不在目标应用，已停止输入；不会自动拉回应用。')
    return _adb(device, ['shell', 'input', *command], runner)


def main(argv=None, *, runner=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True)
    parser.add_argument('--package', required=True)
    commands = parser.add_subparsers(dest='command', required=True)
    input_parser = commands.add_parser('input', help='仅发送触摸或Home/Back导航')
    input_parser.add_argument('arguments', nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    try:
        output = send_input(args.device, args.package, args.arguments, runner=runner)
    except InputRejected as error:
        parser.error(str(error))
    except DeviceInputError as error:
        print(error, file=sys.stderr)
        return 1
    if output.strip():
        print(output.strip())
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
