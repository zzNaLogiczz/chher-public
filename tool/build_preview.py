#!/usr/bin/env python3
"""Build the universal chher-preview app on its independent 90.x.y version line."""
from pathlib import Path
import datetime
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parent.parent
PACKAGE = 'com.chhreader.chh_app.preview'
LABEL = 'chher-preview'
ABIS = ('armeabi-v7a', 'arm64-v8a', 'x86_64')


def main():
    if len(sys.argv) != 2:
        raise SystemExit('用法: python3 tool/build_preview.py 90.0.1')
    version = sys.argv[1]
    match = re.fullmatch(r'90\.(\d{1,2})\.(\d{1,2})', version)
    if not match or tuple(map(int, version.split('.'))) < (90, 0, 1):
        raise SystemExit('测试版本从 90.0.1 开始，仅使用 90.x.y；minor/patch 为 0–99')
    major, minor, patch = map(int, version.split('.'))
    if version != f'{major}.{minor}.{patch}':
        raise SystemExit('版本数字不能包含前导零')
    code = major * 10000 + minor * 100 + patch
    formal = re.search(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$', (ROOT / 'pubspec.yaml').read_text(), re.M)
    if formal is None:
        raise SystemExit('无法识别正式版版本，停止测试构建')
    def restore_formal_version():
        local = ROOT / 'android/local.properties'
        if not local.exists():
            return
        text = local.read_text()
        for key, value in [('flutter.versionName', formal[1]), ('flutter.versionCode', formal[2])]:
            text = re.sub(r'^' + re.escape(key) + r'=.*$', key + '=' + value, text, flags=re.M)
        local.write_text(text)
    out = ROOT / 'build' / 'preview' / version
    apk = out / f'{LABEL}-{version}.apk'
    if apk.exists():
        raise SystemExit(f'{apk} 已存在；新的测试交付请递增版本')
    init = Path.home() / '.gradle/init.d/chher-isolated-preview.gradle'
    if init.exists():
        raise SystemExit(f'已有临时构建配置，拒绝覆盖: {init}')
    template = (ROOT / 'tool/preview_package.gradle').read_text()
    app_dir = str(ROOT / 'android/app').replace('\\', '\\\\').replace("'", "\\'")
    content = template.replace(
        "project.name == 'app' &&",
        f"project.name == 'app' && project.projectDir.canonicalPath == '{app_dir}' &&",
    ).replace('Chher-preview', LABEL)
    out.mkdir(parents=True, exist_ok=True)
    init.parent.mkdir(parents=True, exist_ok=True)
    init.write_text(content)
    stamp = 'preview-' + datetime.datetime.now().strftime('%Y%m%d%H%M')
    try:
        command = [
            'flutter', '--no-version-check', 'build', 'apk', '--release',
            '--target-platform=android-arm,android-arm64,android-x64',
            '--target=lib/main.dart',
            f'--build-name={version}', f'--build-number={code}',
            f'--dart-define=app_version={version}',
            f'--dart-define=build_stamp={stamp}',
        ]
        with (out / 'build.log').open('w') as log:
            subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
    finally:
        # Only remove this script's exact file, preserving any external edits.
        if init.exists() and init.read_text() == content:
            init.unlink()
        restore_formal_version()
    built = ROOT / 'build/app/outputs/flutter-apk/app-release.apk'
    sdk = Path(os.environ.get('ANDROID_HOME', str(Path.home() / 'Library/Android/sdk')))
    tools = sorted((sdk / 'build-tools').glob('*/aapt2'), key=lambda p: tuple(map(int, re.findall(r'\d+', p.parent.name))))
    if not tools:
        raise SystemExit('找不到 aapt2，未交付未经核对的 APK')
    badging = subprocess.check_output([str(tools[-1]), 'dump', 'badging', str(built)], text=True)
    package = re.search(r"^package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", badging, re.M)
    label = re.search(r"^application-label:'([^']+)'", badging, re.M)
    if not package or package.groups() != (PACKAGE, str(code), version) or not label or label[1] != LABEL:
        raise SystemExit('APK 身份与测试构建要求不符；未复制交付文件')
    with ZipFile(built) as archive:
        entries = set(archive.namelist())
        for abi in ABIS:
            for library in ('libapp.so', 'libflutter.so'):
                if f'lib/{abi}/{library}' not in entries:
                    raise SystemExit(f'通用 APK 缺少 {abi}/{library}；未复制交付文件')
    shutil.copy2(built, apk)
    digest = hashlib.sha256(apk.read_bytes()).hexdigest()
    (out / 'identity.json').write_text(json.dumps({
        'package': PACKAGE, 'label': LABEL, 'versionName': version,
        'versionCode': code, 'entrypoint': 'lib/main.dart',
        'abis': ABIS,
        'sha256': digest, 'stamp': stamp,
    }, ensure_ascii=False, indent=2) + '\n')
    print(f'完整测试 App: {apk}\n版本: {version}+{code}\nSHA256: {digest}')


if __name__ == '__main__':
    main()
