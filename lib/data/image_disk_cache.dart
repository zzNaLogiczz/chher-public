import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Bounded on-disk store for downloaded forum images, one file per URL.
///
/// Design constraints:
/// - The hit path performs no write of any kind (no mtime touch). Access
///   order lives only in memory ([_entries], oldest first).
/// - The directory is scanned once, lazily; afterwards [_total] is a running
///   value, so neither eviction nor [totalBytes] ever walks the directory.
/// - Files are written to a temp name and renamed, so a half-written image is
///   never visible as a hit.
/// - The directory is reclaimable by the OS: a missing file is a miss.
/// - A `null` directory turns every method into a silent no-op.
///
/// After a restart the access order is unknown, so the initial scan seeds it
/// from file mtime (which is the last write time, not the last read time). The
/// cache is therefore FIFO-by-write across restarts and true LRU within a
/// session; this is the price of keeping reads write-free.
class ImageDiskCache {
  ImageDiskCache(
    this._dir, {
    this.maxBytes = 200 << 20,
    this.evictTo = 0.9,
    this.maxConcurrentReads = 4,
    @visibleForTesting Future<Uint8List> Function(File)? readFile,
  }) : assert(maxConcurrentReads > 0),
       _readFile = readFile ?? ((file) => file.readAsBytes());

  final int maxConcurrentReads;
  final Future<Uint8List> Function(File) _readFile;
  final Queue<Completer<void>> _readWaiters = Queue();
  int _activeReads = 0;

  Future<void> _acquireRead() async {
    if (_activeReads < maxConcurrentReads) {
      _activeReads++;
    } else {
      final waiter = Completer<void>();
      _readWaiters.add(waiter);
      await waiter.future;
    }
  }

  void _releaseRead() {
    if (_readWaiters.isEmpty) {
      _activeReads--;
    } else {
      _readWaiters.removeFirst().complete();
    }
  }

  final Directory? _dir;
  final int maxBytes;
  final double evictTo;

  @visibleForTesting
  int hits = 0;
  @visibleForTesting
  int misses = 0;

  /// url-hash file name -> byte size, least recently used first.
  final LinkedHashMap<String, int> _entries = LinkedHashMap<String, int>();
  int _total = 0;
  int _writeEpoch = 0;
  Future<void>? _scan;
  Future<void> _writes = Future<void>.value();

  Future<Uint8List?> read(String url) async {
    final dir = _dir;
    if (dir == null) return null;
    await _ensureScanned();
    await _acquireRead();
    try {
      final name = _fileName(url);
      if (!_entries.containsKey(name)) {
        misses++;
        return null;
      }
      final epoch = _writeEpoch;
      try {
        final data = await _readFile(File('${dir.path}/$name'));
        // Re-check: an eviction or clear may have run while we were reading.
        final size = _entries.remove(name);
        if (size == null) {
          misses++;
          return null;
        }
        _entries[name] = size;
        hits++;
        return data;
      } catch (_) {
        // Vanished or unreadable: forget it and treat as a miss.
        // Skip if a write completed meanwhile: it may have re-added this name.
        if (epoch == _writeEpoch) _forget(name);
        misses++;
        return null;
      }
    } finally {
      _releaseRead();
    }
  }

  Future<void> write(String url, Uint8List bytes) {
    if (_dir == null || bytes.isEmpty) return Future<void>.value();
    return _enqueue(() => _write(url, bytes));
  }

  /// Total cached bytes. Cheap after the first call (running value).
  Future<int> totalBytes() async {
    if (_dir == null) return 0;
    await _ensureScanned();
    await _writes;
    return _total;
  }

  Future<void> clear() {
    final dir = _dir;
    if (dir == null) return Future<void>.value();
    return _enqueue(() async {
      await _ensureScanned();
      _entries.clear();
      _total = 0;
      try {
        await for (final e in dir.list(followLinks: false)) {
          if (e is File) await _tryDelete(e);
        }
      } catch (_) {
        // Best effort.
      }
    });
  }

  Future<void> _write(String url, Uint8List bytes) async {
    final dir = _dir!;
    await _ensureScanned();
    final name = _fileName(url);
    final temporary = File('${dir.path}/$name.tmp');
    try {
      await dir.create(recursive: true);
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename('${dir.path}/$name');
    } catch (_) {
      // Full disk or reclaimed directory: skip caching, never throw. Remove the
      // partial temp file, which is in neither the index nor the total.
      await _tryDelete(temporary);
      return;
    }
    final old = _entries.remove(name);
    if (old != null) _total -= old;
    _entries[name] = bytes.length;
    _total += bytes.length;
    _writeEpoch++;
    _evictIfNeeded();
  }

  /// Picks victims synchronously (O(evicted)) so that reads see the new state
  /// immediately; the file deletions run in the background write chain.
  void _evictIfNeeded() {
    // Reaching the ceiling triggers eviction, so the store never rests above it.
    if (_total < maxBytes) return;
    final target = (maxBytes * evictTo).floor();
    final victims = <String>[];
    while (_total > target && _entries.isNotEmpty) {
      final name = _entries.keys.first;
      _total -= _entries.remove(name)!;
      victims.add(name);
    }
    final dir = _dir!;
    _enqueue(() async {
      for (final name in victims) {
        // A write queued before this job may have re-added the name; keep it.
        if (_entries.containsKey(name)) continue;
        await _tryDelete(File('${dir.path}/$name'));
      }
    });
  }

  void _forget(String name) {
    final size = _entries.remove(name);
    if (size != null) _total -= size;
  }

  Future<void> _ensureScanned() => _scan ??= _scanDirectory();

  Future<void> _scanDirectory() async {
    final found = <MapEntry<String, FileStat>>[];
    try {
      final dir = _dir!;
      if (await dir.exists()) {
        await for (final e in dir.list(followLinks: false)) {
          if (e is! File) continue;
          final name = e.uri.pathSegments.last;
          if (!name.endsWith(_suffix)) {
            // Leftover temp file from an interrupted write.
            await _tryDelete(e);
            continue;
          }
          found.add(MapEntry(name, await e.stat()));
        }
      }
    } catch (_) {
      // Unreadable directory: start with an empty index.
    }
    found.sort((a, b) => a.value.modified.compareTo(b.value.modified));
    for (final f in found) {
      _entries[f.key] = f.value.size;
      _total += f.value.size;
    }
    _evictIfNeeded();
  }

  Future<void> _enqueue(Future<void> Function() job) {
    return _writes = _writes.then((_) => job()).catchError((_) {});
  }

  static Future<void> _tryDelete(File file) async {
    try {
      await file.delete();
    } catch (_) {
      // Already gone or locked; harmless.
    }
  }

  static const _suffix = '.img';

  /// File name = two 64-bit FNV-1a-style hashes of the UTF-8 URL, each
  /// rendered as 16 zero-padded lowercase hex digits (32 total) + ".img".
  /// Hex only (no separators or traversal) and fixed width regardless of URL
  /// length, so the two halves cannot blur into each other. 128 bits of hash
  /// state makes accidental collisions between distinct URLs negligible; it is
  /// not cryptographic. No `crypto` dependency.
  static String _fileName(String url) {
    var h1 = 0xcbf29ce484222325;
    var h2 = 0x84222325cbf29ce4;
    for (final b in utf8.encode(url)) {
      h1 = ((h1 ^ b) * 0x100000001b3);
      h2 = ((h2 ^ (b + 0x9e)) * 0x1000193 + (h2 >>> 29));
    }
    // Split into unsigned 32-bit halves: toRadixString on a negative int
    // would emit a '-' sign.
    String part(int v) => (v & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
    String hex(int v) => '${part(v >>> 32)}${part(v)}';
    return '${hex(h1)}${hex(h2)}$_suffix';
  }
}

/// 全局磁盘缓存;目录由 setupDependencies 异步就绪后替换,就绪前是 no-op 实例
ImageDiskCache imageDiskCache = ImageDiskCache(null);
