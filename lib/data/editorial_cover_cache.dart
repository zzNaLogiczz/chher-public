/// Reuse full-size images learned while reading, without fetching articles early.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

final editorialCoverCache = EditorialCoverCache();

/// Only article IDs and image URLs are persisted, never article bodies or cookies.
class EditorialCoverCache extends ChangeNotifier {
  static const _capacity = 100;
  static EditorialCoverCache get instance => editorialCoverCache;

  final File _file;
  final Map<int, String> _covers = {};
  Future<void>? _loading;
  Future<void> _writes = Future<void>.value();

  EditorialCoverCache()
    : _file = File('${Directory.systemTemp.path}/chh-editorial-covers-v1.json');

  @visibleForTesting
  EditorialCoverCache.forTesting(File file) : _file = file;

  String? lookup(int aid) => _covers[aid];

  /// Idempotent; values remembered during disk IO take precedence over old data.
  Future<void> load() => _loading ??= _read();

  Future<void> _read() async {
    try {
      if (!await _file.exists()) return;
      final decoded = jsonDecode(await _file.readAsString());
      if (decoded is! Map || decoded['version'] != 1) return;
      final stored = decoded['covers'];
      if (stored is! Map) return;
      final merged = <int, String>{};
      for (final entry in stored.entries) {
        final aid = int.tryParse(entry.key.toString());
        final url = entry.value;
        if (aid != null && aid > 0 && url is String && _validUrl(url)) {
          merged[aid] = url;
        }
      }
      for (final entry in _covers.entries) {
        merged.remove(entry.key);
        merged[entry.key] = entry.value;
      }
      while (merged.length > _capacity) {
        merged.remove(merged.keys.first);
      }
      if (mapEquals(_covers, merged)) return;
      _covers
        ..clear()
        ..addAll(merged);
      notifyListeners();
    } catch (_) {
      // Cache eviction, malformed JSON, and unavailable storage are harmless.
    }
  }

  /// Memory updates synchronously. The returned future completes after its write.
  /// Repeated values are a no-op; writes are serialized and never block rendering.
  Future<void> remember(int aid, String url) {
    final normalized = url.trim();
    if (aid <= 0 || !_validUrl(normalized)) {
      return Future<void>.value();
    }
    if (_covers[aid] == normalized) return _writes;
    _covers.remove(aid);
    _covers[aid] = normalized;
    while (_covers.length > _capacity) {
      _covers.remove(_covers.keys.first);
    }
    notifyListeners();
    return _writes = _writes.then((_) async {
      await load();
      try {
        final payload = jsonEncode({
          'version': 1,
          'covers': _covers.map((aid, image) => MapEntry('$aid', image)),
        });
        await _file.parent.create(recursive: true);
        final temporary = File('${_file.path}.tmp');
        await temporary.writeAsString(payload, flush: true);
        await temporary.rename(_file.path);
      } catch (_) {
        // Rendering and in-memory reuse remain available if storage is full.
      }
    });
  }

  static bool _validUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty;
  }
}
