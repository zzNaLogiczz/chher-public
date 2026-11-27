#!/usr/bin/env python3
"""Build an iOS preview IPA with ad-hoc signatures for TrollStore."""
from contextlib import contextmanager
from datetime import datetime
import fcntl
import hashlib
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
from tempfile import TemporaryDirectory

ROOT = Path(__file__).resolve().parent.parent
PACKAGE = 'com.chhreader.chhApp.preview'
LABEL = 'chhers-preview'


def version_code(version):
    match = re.fullmatch(r'90\.(0|[1-9][0-9]?)\.(0|[1-9][0-9]?)', version)
    if not match or version == '90.0.0':
        raise ValueError('测试版本从 90.0.1 开始，仅使用 90.x.y；数字不含前导零')
    minor, patch = map(int, match.groups())
    return 90 * 10000 + minor * 100 + patch


@contextmanager
def preview_plist(path):
    original = path.read_bytes()
    try:
        for key, value in (
            ('CFBundleDisplayName', LABEL),
            ('CFBundleIdentifier', PACKAGE),
        ):
            subprocess.run(
                ['plutil', '-replace', key, '-string', value, str(path)],
                check=True,
            )
        yield
    finally:
        path.write_bytes(original)


def read_plist(path):
    with path.open('rb') as source:
        return plistlib.load(source)


def sign_app(app, executable, ldid):
    libraries = list(app.rglob('*.dylib'))
    for framework in app.rglob('*.framework'):
        info = framework / 'Info.plist'
        if not info.is_file():
            info = framework / 'Resources/Info.plist'
        libraries.append(framework / read_plist(info)['CFBundleExecutable'])

    # Skip duplicate aliases for versioned frameworks. Sign the main binary last.
    for binary in dict.fromkeys(path.resolve() for path in [*libraries, executable]):
        if not binary.is_relative_to(app) or not binary.is_file():
            raise SystemExit(f'应用内二进制无效：{binary}')
        subprocess.run([ldid, '-S', str(binary)], check=True)


def build_preview(version, code, ldid, out):
    ipa = out / f'{LABEL}-ios-{version}.ipa'
    if ipa.exists():
        raise SystemExit(f'{ipa} 已存在，请递增测试版本')

    stamp = datetime.now().strftime('preview-%Y%m%d%H%M')
    with preview_plist(ROOT / 'ios/Runner/Info.plist'):
        subprocess.run(
            [
                'flutter', 'build', 'ios', '--release', '--no-codesign',
                '--build-name', version, '--build-number', str(code),
                f'--dart-define=app_version={version}',
                f'--dart-define=build_stamp={stamp}',
            ],
            cwd=ROOT,
            check=True,
        )

    built = ROOT / 'build/ios/iphoneos/Runner.app'
    info = read_plist(built / 'Info.plist')
    expected = {
        'CFBundleIdentifier': PACKAGE,
        'CFBundleDisplayName': LABEL,
        'CFBundleShortVersionString': version,
        'CFBundleVersion': str(code),
    }
    for key, value in expected.items():
        if info.get(key) != value:
            raise SystemExit(f'应用的 {key} 为 {info.get(key)!r}，预期为 {value!r}')

    with TemporaryDirectory(dir=out) as tmp:
        staging = Path(tmp).resolve()
        app = staging / 'Payload' / built.name
        shutil.copytree(built, app, symlinks=True)
        sign_app(app, app / info['CFBundleExecutable'], ldid)
        archive = staging / ipa.name
        subprocess.run(
            ['zip', '-qry', str(archive), 'Payload'], cwd=staging, check=True,
        )
        archive.replace(ipa)

    digest = hashlib.sha256()
    with ipa.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(chunk)
    print(f'包名：{PACKAGE}\n显示名：{LABEL}\n版本：{version}\nversionCode：{code}')
    print(f'IPA：{ipa}\n大小：{ipa.stat().st_size} 字节\nSHA256：{digest.hexdigest()}')


def main():
    if len(sys.argv) != 2:
        raise SystemExit('用法：python3 tool/build_ios_preview.py 90.0.1')
    version = sys.argv[1]
    try:
        code = version_code(version)
    except ValueError as error:
        raise SystemExit(str(error)) from None

    ldid = shutil.which('ldid')
    if ldid is None:
        raise SystemExit('找不到 ldid，请先运行 brew install ldid')

    formal = re.search(
        r'^version:[ \t]+([0-9]+\.[0-9]+\.[0-9]+)\+[0-9]+[ \t]*$',
        (ROOT / 'pubspec.yaml').read_text(),
        re.M,
    )
    if formal is None or formal[1].startswith('90.'):
        raise SystemExit('pubspec.yaml 必须使用正式版本，测试版本通过构建参数传入')

    out = ROOT / 'build' / 'preview' / version
    out.mkdir(parents=True, exist_ok=True)
    # Run separately from Android builds in this checkout. This lock serializes
    # iOS preview builds that temporarily edit the same source plist.
    with (ROOT / 'build' / '.ios-preview.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        build_preview(version, code, ldid, out)


if __name__ == '__main__':
    main()
