/// Resolves the app's private files/cache directories from the native side.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Read-only on purpose: it must never register a handler on `chh/update`,
/// which would steal the `installStatus` callback from the app updater.
class AppPaths {
  static final AppPaths instance = AppPaths._(null, null);

  // Injected directories bypass the channel entirely (tests only).
  final Directory? _files;
  final Directory? _cache;
  Future<Map<String, String>?>? _info;

  AppPaths._(this._files, this._cache);

  @visibleForTesting
  AppPaths.forTesting({Directory? files, Directory? cache})
    : this._(files, cache);

  /// Drops the memoized native lookup so the next call asks again.
  @visibleForTesting
  static void resetForTesting() => instance._info = null;

  /// `null` when the platform cannot tell (non-Android, channel failure).
  Future<Directory?> files() async => _files ?? await _resolve('filesDir');

  Future<Directory?> cache() async => _cache ?? await _resolve('cacheDir');

  /// Creates the directory when missing; `null` if unavailable or not creatable.
  Future<Directory?> subdir(String name, {bool inCache = false}) async {
    final base = inCache ? await cache() : await files();
    if (base == null) return null;
    try {
      return await Directory('${base.path}/$name').create(recursive: true);
    } catch (_) {
      // Read-only or full storage must not break callers; they degrade.
      return null;
    }
  }

  Future<Directory?> _resolve(String key) async {
    final path = (await (_info ??= _query()))?[key];
    return path == null ? null : Directory(path);
  }

  /// Memoized so `appInfo` is called at most once per process.
  Future<Map<String, String>?> _query() async {
    try {
      final raw = await const MethodChannel(
        'chh/update',
      ).invokeMethod<Map>('appInfo');
      final files = raw?['filesDir'];
      final cache = raw?['cacheDir'];
      if (files is! String || cache is! String) return null;
      return {'filesDir': files, 'cacheDir': cache};
    } catch (_) {
      // MissingPluginException off Android, PlatformException on native errors.
      return null;
    }
  }
}
