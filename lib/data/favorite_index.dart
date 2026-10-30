/// 收藏按账号隔离,未取得目录时先保存在内存。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/chh_urls.dart';
import '../models/models.dart';

class FavoriteTarget {
  final FavoriteType type;
  final int targetId;
  final String title;
  const FavoriteTarget({
    required this.type,
    required this.targetId,
    required this.title,
  });
}

class FavoriteToggle {
  final bool favorited;
  const FavoriteToggle(this.favorited);
}

class FavoriteIndex extends ChangeNotifier {
  File? _file;
  int? _uid;
  int _epoch = 0;
  int _replacement = 0;
  bool _disposed = false;
  bool _authoritative = false;
  bool _dirty = false;
  Future<void>? _loading;
  Future<void> _writes = Future.value();
  final Map<String, FavoriteItem> _entries = {};
  final Set<String> _removed = {};
  DateTime? _lastSyncedAt;

  FavoriteIndex(this._file);

  int? get uid => _uid;
  int get epoch => _epoch;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  List<FavoriteItem> get items => List.unmodifiable(_entries.values);
  String _key(FavoriteType type, int id) => '${type.name}:$id';
  String? _itemKey(FavoriteItem item) =>
      item.type == FavoriteType.all ||
          item.targetId == null ||
          item.targetId! <= 0
      ? null
      : _key(item.type, item.targetId!);
  bool contains(FavoriteTarget target) => entryFor(target) != null;
  FavoriteItem? entryFor(FavoriteTarget target) =>
      _entries[_key(target.type, target.targetId)];

  void setUid(int? uid) {
    if (_uid == uid) return;
    _uid = uid;
    _epoch++;
    _entries.clear();
    _removed.clear();
    _lastSyncedAt = null;
    _authoritative = false;
    _loading = null;
    _dirty = true;
    notifyListeners();
    // uid 可能晚于目录就绪;重新读取才能恢复启动时同账号的收藏。
    if (_file != null) unawaited(flush());
  }

  Future<void> attach(File? file) async {
    _file = file;
    _loading = null;
    await load();
    if (_dirty) await flush();
  }

  Future<void> load() => _loading ??= _read();

  Future<void> _read() async {
    final file = _file;
    final uid = _uid;
    final epoch = _epoch;
    final replacement = _replacement;
    if (file == null || uid == null || _authoritative) return;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (_disposed ||
          _authoritative ||
          epoch != _epoch ||
          replacement != _replacement ||
          decoded is! Map ||
          decoded['version'] != 1 ||
          decoded['uid'] != uid) {
        return;
      }
      final raw = decoded['items'];
      if (raw is! List) return;
      final stored = <String, FavoriteItem>{};
      for (final value in raw) {
        if (value is! Map) continue;
        final type = FavoriteType.values
            .where((t) => t.name == value['type'])
            .firstOrNull;
        final id = value['targetId'];
        if (type == null ||
            type == FavoriteType.all ||
            id is! int ||
            id <= 0 ||
            value['favid'] is! String ||
            value['title'] is! String) {
          continue;
        }
        final item = FavoriteItem(
          type: type,
          targetId: id,
          favid: value['favid'] as String,
          title: value['title'] as String,
          url: value['url'] is String ? value['url'] as String : '',
        );
        final key = _itemKey(item)!;
        if (!_removed.contains(key)) stored[key] = item;
      }
      // 读取期间发生的用户操作优先于磁盘旧值。
      final current = Map<String, FavoriteItem>.of(_entries);
      stored.removeWhere((key, _) => current.containsKey(key));
      _entries
        ..clear()
        ..addAll(current)
        ..addAll(stored);
      final syncedAt = decoded['syncedAt'];
      _lastSyncedAt ??= syncedAt is int
          ? DateTime.fromMillisecondsSinceEpoch(syncedAt)
          : null;
      notifyListeners();
    } catch (_) {
      // 存储不可用不影响当前会话收藏。
    }
  }

  void merge(Iterable<FavoriteItem> items, {bool prepend = false}) {
    if (_uid == null) return;
    final incoming = <String, FavoriteItem>{};
    for (final item in items) {
      final key = _itemKey(item);
      if (key != null) {
        incoming[key] = item;
        _removed.remove(key);
      }
    }
    if (incoming.isEmpty) return;
    // 首页包含最近收藏,其他页只补条目,不改变已知顺序。
    if (prepend) {
      final previous = Map<String, FavoriteItem>.of(_entries)
        ..removeWhere((key, _) => incoming.containsKey(key));
      _entries
        ..clear()
        ..addAll(incoming)
        ..addAll(previous);
    } else {
      _entries.addAll(incoming);
    }
    _changed();
  }

  void replace(Iterable<FavoriteItem> items, {DateTime? syncedAt}) {
    if (_uid == null) return;
    _replacement++;
    _authoritative = true;
    _entries.clear();
    _removed.clear();
    for (final item in items) {
      final key = _itemKey(item);
      if (key != null) _entries[key] = item;
    }
    _lastSyncedAt = syncedAt;
    _changed();
  }

  void put(FavoriteTarget target, {String favid = ''}) {
    if (_uid == null) return;
    final key = _key(target.type, target.targetId);
    final old = _entries.remove(key);
    final item = FavoriteItem(
      type: target.type,
      targetId: target.targetId,
      favid: favid.isEmpty ? old?.favid ?? '' : favid,
      title: target.title,
      url: switch (target.type) {
        FavoriteType.thread => ChhUrls.thread(target.targetId).toString(),
        FavoriteType.forum => ChhUrls.threadList(target.targetId).toString(),
        _ => ChhUrls.article(target.targetId).toString(),
      },
    );
    final previous = Map<String, FavoriteItem>.of(_entries);
    _entries.clear();
    _entries[key] = item;
    _entries.addAll(previous);
    _removed.remove(key);
    _changed();
  }

  void remove(FavoriteTarget target) {
    final key = _key(target.type, target.targetId);
    _entries.remove(key);
    _removed.add(key);
    _changed();
  }

  void _changed() {
    _dirty = true;
    if (!_disposed) notifyListeners();
    if (_file != null) unawaited(flush());
  }

  Future<void> flush() => _writes = _writes.then((_) async {
    await load();
    final file = _file;
    if (file == null || !_dirty) return;
    _dirty = false;
    final payload = jsonEncode({
      'version': 1,
      'uid': _uid,
      'syncedAt': _lastSyncedAt?.millisecondsSinceEpoch,
      'items': _entries.values
          .map(
            (e) => {
              'type': e.type.name,
              'targetId': e.targetId,
              'favid': e.favid,
              'title': e.title,
              'url': e.url,
            },
          )
          .toList(),
    });
    try {
      await file.parent.create(recursive: true);
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(payload, flush: true);
      await temp.rename(file.path);
    } catch (_) {
      // 下次更新仍可重试落盘。
    }
  });

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
