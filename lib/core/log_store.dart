/// Segmented on-disk store for diagnostic log lines.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Appends lines to `log-<n>.txt` segments inside [dir]. Evicting the oldest
/// data deletes one file instead of rewriting a large one.
///
/// Lines are stored verbatim; this class never inspects or logs their content.
/// Every IO failure is swallowed so storage problems never reach callers.
class LogStore {
  LogStore(this.dir, {this.segmentBytes = 1 << 20, this.maxSegments = 10});

  final Directory dir;
  final int segmentBytes;
  final int maxSegments;

  static final _segmentName = RegExp(r'[/\\]log-(\d+)\.txt$');

  final List<String> _queue = [];
  Future<void> _writes = Future<void>.value();

  /// Memory only: never touches IO and never starts a timer.
  void enqueue(String line) => _queue.add(line);

  /// Writes queued lines, rotating and evicting segments as needed.
  Future<void> flush() => _writes = _writes.then((_) => _write());

  /// Streams stored lines oldest first, one segment at a time.
  Stream<String> dump() async* {
    // Wait for in-flight writes so a segment is never read half-rotated.
    await _writes;
    for (final segment in await _segments()) {
      try {
        yield* segment
            .openRead()
            .transform(const Utf8Decoder(allowMalformed: true))
            .transform(const LineSplitter());
      } catch (_) {
        // An unreadable segment is skipped.
      }
    }
  }

  Future<int> totalBytes() async {
    await _writes;
    var total = 0;
    for (final segment in await _segments()) {
      try {
        total += await segment.length();
      } catch (_) {}
    }
    return total;
  }

  /// Drops queued lines immediately, then deletes every segment.
  Future<void> clear() {
    _queue.clear();
    return _writes = _writes.then((_) async {
      for (final segment in await _segments()) {
        try {
          await segment.delete();
        } catch (_) {}
      }
    });
  }

  Future<void> _write() async {
    if (_queue.isEmpty) return;
    final lines = List<String>.of(_queue);
    _queue.clear();
    try {
      if (!await dir.exists()) return;
      final segments = await _segments();
      var index = segments.isEmpty ? 0 : _indexOf(segments.last);
      var size = segments.isEmpty ? 0 : await segments.last.length();
      var buffer = StringBuffer();
      for (final line in lines) {
        final bytes = utf8.encode(line).length + 1;
        if (size > 0 && size + bytes > segmentBytes) {
          await _append(index, buffer);
          buffer = StringBuffer();
          index++;
          size = 0;
        }
        buffer.writeln(line);
        size += bytes;
      }
      await _append(index, buffer);
      await _evict();
    } catch (_) {
      // Lines that cannot be persisted are dropped; logging must stay harmless.
    }
  }

  Future<void> _append(int index, StringBuffer buffer) {
    return File(
      '${dir.path}/log-$index.txt',
    ).writeAsString(buffer.toString(), mode: FileMode.append, flush: true);
  }

  Future<void> _evict() async {
    final segments = await _segments();
    for (var i = 0; i < segments.length - maxSegments; i++) {
      try {
        await segments[i].delete();
      } catch (_) {}
    }
  }

  /// Existing segments sorted by index; empty if [dir] is missing.
  Future<List<File>> _segments() async {
    try {
      final files = [
        await for (final e in dir.list())
          if (e is File && _segmentName.hasMatch(e.path)) e,
      ];
      files.sort((a, b) => _indexOf(a).compareTo(_indexOf(b)));
      return files;
    } catch (_) {
      return [];
    }
  }

  static int _indexOf(File file) =>
      int.parse(_segmentName.firstMatch(file.path)![1]!);
}
