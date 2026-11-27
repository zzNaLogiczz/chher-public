#!/usr/bin/env python3
"""Validate private dart-define JSON without printing service addresses."""
import json
import sys
from pathlib import Path
from urllib.parse import urlsplit

INVALID_CONFIG = '更新配置无效，请检查本地配置文件。'


def _validate_endpoints(endpoints):
    if not isinstance(endpoints, str):
        raise ValueError('type')
    if not endpoints:
        return
    for raw in endpoints.split(','):
        endpoint = raw.strip()
        uri = urlsplit(endpoint)
        if (not endpoint or any(c.isspace() for c in endpoint)
                or uri.scheme not in ('http', 'https') or not uri.hostname
                or uri.username is not None or uri.password is not None
                or uri.path not in ('', '/') or uri.query or uri.fragment
                or '?' in endpoint or '#' in endpoint
                or (uri.port is not None and not 1 <= uri.port <= 65535)):
            raise ValueError('endpoint')


def validate(path):
    """Return the validated address list, or an empty string when disabled."""
    try:
        value = json.loads(Path(path).read_text(encoding='utf-8'))
        if not isinstance(value, dict) or set(value) != {'CHH_UPDATE_ENDPOINTS'}:
            raise ValueError('keys')
        endpoints = value['CHH_UPDATE_ENDPOINTS']
        _validate_endpoints(endpoints)
        return endpoints
    except (OSError, ValueError, RecursionError):
        raise ValueError(INVALID_CONFIG) from None


if __name__ == '__main__':
    try:
        if len(sys.argv) != 2:
            raise ValueError('arguments')
        validate(sys.argv[1])
    except ValueError:
        raise SystemExit(INVALID_CONFIG) from None
