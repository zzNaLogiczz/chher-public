/// Local ledger of which threads the user has opened, and at what reply count.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Backed by memory until `di.dart` attaches the real file.
final ThreadReadIndex threadReadIndex = ThreadReadIndex(null);

/// How a thread should be marked in a list.
sealed class ThreadReadState {
  const ThreadReadState();
}

/// Never opened. Deliberately not marked "new": on a first visit the whole
/// screen would be new and the signal worthless.
class ThreadReadUnseen extends ThreadReadState {
  const ThreadReadUnseen();
}

/// Opened, and the reply count has not grown since.
class ThreadReadSeen extends ThreadReadState {
  const ThreadReadSeen();
}

/// Opened, and [count] replies have arrived since.
class ThreadReadNewReplies extends ThreadReadState {
  final int count;
  const ThreadReadNewReplies(this.count);
}

class _Entry {
  final int replies;
  final int at;
  const _Entry(this.replies, this.at);
}

/// Per-thread "reply count at last open", persisted as
/// `{"version":1,"threads":{"<tid>":{"r":<replies>,"at":<epochMs>}}}`.
///
/// Deliberately global: not partitioned by uid and not cleared on logout.
/// This is reading history on this device, and guest browsing counts. It
/// differs on purpose from the two-level discussion index in docs/DESIGN.md,
/// which is cleared when the account changes: that is a within-session
/// projection of content, this is cross-session history. Do not "fix" it.
///
/// Every storage failure degrades silently to "nothing has been seen".
class ThreadReadIndex extends ChangeNotifier {
  final int capacity;
  final Duration writeDelay;

  File? _file;
  // Insertion order doubles as recency; see _evict for the tie-break.
  final Map<int, _Entry> _entries = {};
  Future<void>? _loading;
  Future<void> _writes = Future<void>.value();
  Timer? _timer;
  bool _dirty = false;
  bool _disposed = false;

  /// [file] `null` means memory only. [writeDelay] is how long disk waits for
  /// further marks before one write covers them all.
  ThreadReadIndex(
    this._file, {
    this.capacity = 2000,
    this.writeDelay = const Duration(seconds: 2),
  });

  /// Idempotent. Marks made before the read completes win over old disk data.
  Future<void> load() => _loading ??= _read();

  /// Points the index at its file once the directory is known, keeping
  /// listeners and anything marked in memory so far.
  Future<void> attach(File? file) {
    _file = file;
    _loading = null;
    if (_entries.isNotEmpty) _scheduleWrite();
    return load();
  }

  Future<void> _read() async {
    final file = _file;
    if (file == null) return;
    try {
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map || decoded['version'] != 1) return;
      final stored = decoded['threads'];
      if (stored is! Map) return;
      final merged = <int, _Entry>{};
      for (final item in stored.entries) {
        final tid = int.tryParse(item.key.toString());
        final value = item.value;
        if (tid == null || tid <= 0 || value is! Map) continue;
        final r = value['r'];
        final at = value['at'];
        if (r is int && r >= 0 && at is int) merged[tid] = _Entry(r, at);
      }
      // In-memory marks are newer than anything on disk.
      for (final item in _entries.entries) {
        merged.remove(item.key);
        merged[item.key] = item.value;
      }
      _entries
        ..clear()
        ..addAll(merged);
      _evict();
      if (!_disposed) notifyListeners();
    } catch (_) {
      // Malformed JSON and unavailable storage mean "nothing seen", not an error.
    }
  }

  /// Memory updates synchronously so the UI can repaint at once; disk catches
  /// up after the debounce. Same count again is a no-op.
  void markRead(int tid, int replies) {
    if (tid <= 0 || replies < 0) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final unchanged = _entries[tid]?.replies == replies;
    _entries.remove(tid);
    _entries[tid] = _Entry(replies, now);
    _scheduleWrite();
    // A repeat open only refreshes `at` (last-opened, so it ages out last);
    // nothing visible changed, so no repaint and no eviction.
    if (unchanged) return;
    _evict(keep: tid);
    notifyListeners();
  }

  /// A lower [replies] than recorded (posts get deleted) is still seen.
  /// Without [replies] an opened thread is simply seen.
  ThreadReadState stateOf(int tid, {int? replies}) {
    final entry = _entries[tid];
    if (entry == null) return const ThreadReadUnseen();
    if (replies != null && replies > entry.replies) {
      return ThreadReadNewReplies(replies - entry.replies);
    }
    return const ThreadReadSeen();
  }

  /// Completes once everything marked so far is on disk (or storage failed,
  /// which is swallowed). Cancels the pending debounce.
  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    return _persist();
  }

  void _evict({int? keep}) {
    while (_entries.length > capacity) {
      int? oldest;
      var oldestAt = 0;
      // Strict `<` keeps the earliest-inserted among equal timestamps.
      for (final item in _entries.entries) {
        // Skip the just-marked thread: clock skew must not make it evict itself.
        if (item.key == keep) continue;
        if (oldest == null || item.value.at < oldestAt) {
          oldest = item.key;
          oldestAt = item.value.at;
        }
      }
      _entries.remove(oldest);
    }
  }

  void _scheduleWrite() {
    _dirty = true;
    if (_file == null || _disposed) return;
    _timer?.cancel();
    _timer = Timer(writeDelay, () {
      _timer = null;
      unawaited(_persist());
    });
  }

  /// Serialized behind earlier writes; a write after another has already
  /// covered the same state is skipped.
  Future<void> _persist() {
    return _writes = _writes.then((_) async {
      await load();
      final file = _file;
      if (file == null || !_dirty) return;
      _dirty = false;
      try {
        final payload = jsonEncode({
          'version': 1,
          'threads': _entries.map(
            (tid, e) => MapEntry('$tid', {'r': e.replies, 'at': e.at}),
          ),
        });
        await file.parent.create(recursive: true);
        final temporary = File('${file.path}.tmp');
        await temporary.writeAsString(payload, flush: true);
        await temporary.rename(file.path);
      } catch (_) {
        // In-memory marks keep working if storage is full or gone.
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
