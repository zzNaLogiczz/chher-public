import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

final HistoryIndex historyIndex = HistoryIndex(null);

enum HistoryType { thread, article }

class HistoryEntry {
  final HistoryType type;
  final int id;
  final String title;
  final int? fid;
  final String? forumName;
  final String? column;
  final String author;
  final DateTime at;

  const HistoryEntry._({
    required this.type,
    required this.id,
    required this.title,
    this.fid,
    this.forumName,
    this.column,
    required this.author,
    required this.at,
  });

  String get key => '${type.name}:$id';
}

typedef _Visit = ({HistoryEntry entry, int order});

/// Device-local history. The persisted map is ordered oldest to newest; this
/// preserves visit order even when visits share a timestamp or the clock moves.
class HistoryIndex extends ChangeNotifier {
  static const capacity = 1000;
  static const writeDelay = Duration(seconds: 2);

  File? _file;
  final _entries = <String, _Visit>{};
  Future<void>? _loading;
  Future<void> _writes = Future<void>.value();
  Timer? _timer;
  int _visitOrder = 0;
  int _removalOrder = 0;
  bool _dirty = false;
  bool _disposed = false;

  HistoryIndex(this._file);

  List<HistoryEntry> get all => List.unmodifiable(
    _entries.values.map((visit) => visit.entry).toList().reversed,
  );

  Future<void> load() => _loading ??= _read();

  Future<void> attach(File? file) {
    _file = file;
    _loading = null;
    if (_dirty) _scheduleWrite();
    return load();
  }

  Future<void> _read() async {
    final file = _file;
    if (file == null) return;
    try {
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString());
      if (data is! Map || data['version'] != 1) return;
      final stored = data['entries'];
      if (stored is! Map) return;
      final merged = <String, _Visit>{};
      var order = -stored.length;
      for (final item in stored.entries) {
        final key = item.key;
        final value = item.value;
        if (key is! String || value is! Map || _entries.containsKey(key)) {
          continue;
        }
        final entry = _decode(key, value);
        if (entry != null) merged[entry.key] = (entry: entry, order: order++);
      }
      _entries
        ..forEach((key, visit) => merged[key] = visit)
        ..clear()
        ..addAll(merged);
      _trim();
      if (!_disposed) notifyListeners();
    } catch (_) {
      // History remains usable in memory when storage is corrupt or unavailable.
    }
  }

  static HistoryEntry? _decode(String key, Map value) {
    final parts = key.split(':');
    if (parts.length != 2) return null;
    final type = switch (parts.first) {
      'thread' => HistoryType.thread,
      'article' => HistoryType.article,
      _ => null,
    };
    final id = int.tryParse(parts.last);
    final title = value['title'];
    final author = value['author'];
    final at = value['at'];
    if (type == null ||
        id == null ||
        id <= 0 ||
        key != '${type.name}:$id' ||
        title is! String ||
        author is! String ||
        at is! int ||
        at < -8640000000000000 ||
        at > 8640000000000000) {
      return null;
    }
    return HistoryEntry._(
      type: type,
      id: id,
      title: title,
      fid: value['fid'] is int ? value['fid'] : null,
      forumName: value['forumName'] is String ? value['forumName'] : null,
      column: value['column'] is String ? value['column'] : null,
      author: author,
      at: DateTime.fromMillisecondsSinceEpoch(at),
    );
  }

  /// Call when the content has opened successfully.
  void record({
    required HistoryType type,
    required int id,
    required String title,
    required String author,
    int? fid,
    String? forumName,
    String? column,
    DateTime? at,
  }) {
    if (id <= 0) return;
    final isThread = type == HistoryType.thread;
    final entry = HistoryEntry._(
      type: type,
      id: id,
      title: title,
      author: author,
      fid: isThread ? fid : null,
      forumName: isThread ? forumName : null,
      column: isThread ? null : column,
      at: at ?? DateTime.now(),
    );
    _entries.remove(entry.key);
    _entries[entry.key] = (entry: entry, order: _visitOrder++);
    _trim();
    _changed();
  }

  /// The returned callback can undo the latest removal once.
  Future<VoidCallback?> remove(String key) async {
    await load();
    final removed = _entries.remove(key);
    return removed == null ? null : _undoRemoval([removed]);
  }

  /// The returned callback can restore the cleared entries in their old order.
  Future<VoidCallback?> clear() async {
    await load();
    if (_entries.isEmpty) return null;
    final removed = _entries.values.toList();
    _entries.clear();
    return _undoRemoval(removed);
  }

  VoidCallback _undoRemoval(List<_Visit> removed) {
    final removal = ++_removalOrder;
    _changed();
    return () {
      if (_disposed || removal != _removalOrder) return;
      _removalOrder++;
      for (final visit in removed) {
        _entries.putIfAbsent(visit.entry.key, () => visit);
      }
      final ordered = _entries.values.toList()
        ..sort((a, b) => a.order.compareTo(b.order));
      _entries
        ..clear()
        ..addEntries(ordered.map((visit) => MapEntry(visit.entry.key, visit)));
      _trim();
      _changed();
    };
  }

  void _trim() {
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
  }

  void _changed() {
    _dirty = true;
    _scheduleWrite();
    if (!_disposed) notifyListeners();
  }

  void _scheduleWrite() {
    if (_file == null || _disposed) return;
    _timer?.cancel();
    _timer = Timer(writeDelay, () {
      _timer = null;
      unawaited(_persist());
    });
  }

  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    return _persist();
  }

  Future<void> _persist() => _writes = _writes.then((_) async {
    await load();
    final file = _file;
    if (file == null || !_dirty) return;
    _dirty = false;
    try {
      final payload = jsonEncode({
        'version': 1,
        'entries': {
          for (final visit in _entries.values)
            visit.entry.key: {
              'title': visit.entry.title,
              'fid': visit.entry.fid,
              'forumName': visit.entry.forumName,
              'column': visit.entry.column,
              'author': visit.entry.author,
              'at': visit.entry.at.millisecondsSinceEpoch,
            },
        },
      });
      await file.parent.create(recursive: true);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(payload, flush: true);
      await tmp.rename(file.path);
    } catch (_) {
      _dirty = true;
    }
  });

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
