#!/usr/bin/env python3
"""Validate private voice settings and select the release voice source."""
import json
import re
import sys
from pathlib import Path

if __package__:
    from . import update_build_config
else:
    import update_build_config

CREDENTIALS = ('CHH_VOICE_APP_ID', 'CHH_VOICE_SECRET_ID', 'CHH_VOICE_SECRET_KEY')
ENGINE = 'CHH_VOICE_ENGINE'
TOKEN = re.compile(r'[A-Za-z0-9._~-]+')
INVALID_CONFIG = '语音配置无效，请检查本地配置文件。'
CONFLICT = '更新服务已配置，不能同时内置语音密钥。'


def validate(path):
    """Return whether local credentials are enabled."""
    try:
        values = json.loads(Path(path).read_text(encoding='utf-8'))
    except (OSError, ValueError, RecursionError):
        raise ValueError(INVALID_CONFIG) from None
    if not isinstance(values, dict) or set(values) != {*CREDENTIALS, ENGINE}:
        raise ValueError(INVALID_CONFIG)
    if not all(isinstance(value, str) for value in values.values()):
        raise ValueError(INVALID_CONFIG)
    app_id, secret_id, secret_key = (values[key] for key in CREDENTIALS)
    if not any((app_id, secret_id, secret_key)):
        return False
    engine = values[ENGINE]
    if (not re.fullmatch(r'[0-9]+', app_id) or not TOKEN.fullmatch(secret_id)
            or not TOKEN.fullmatch(secret_key) or (engine and not TOKEN.fullmatch(engine))):
        raise ValueError(INVALID_CONFIG)
    return True


def release_source(voice_path, update_path):
    update_enabled = update_path.exists() and bool(update_build_config.validate(update_path))
    voice_enabled = voice_path.exists() and validate(voice_path)
    if voice_enabled and update_enabled:
        raise ValueError(CONFLICT)
    if voice_enabled:
        return '本机密钥'
    if update_enabled:
        return '服务器签发'
    return '未配置'


if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit('用法: python3 tool/voice_build_config.py <语音配置> <更新配置>')
    try:
        print(release_source(Path(sys.argv[1]), Path(sys.argv[2])))
    except (OSError, ValueError) as error:
        message = str(error) if isinstance(error, ValueError) else INVALID_CONFIG
        raise SystemExit(message) from None
