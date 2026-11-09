/// Device-local CHH user blocks; matching is always by stable UID.
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

final UserBlockIndex userBlockIndex = UserBlockIndex(null);

class BlockedUser {
  final String uid;
  final String name;
  final String? avatarUrl;
  final DateTime blockedAt;
  const BlockedUser({
    required this.uid,
    required this.name,
    this.avatarUrl,
    required this.blockedAt,
  });
}

class UserBlockIndex extends ChangeNotifier {
  File? _file;
  final _entries = <String, BlockedUser>{};
  final _overridden = <String>{};
  Future<void>? _loading;
  Future<bool> _writes = Future.value(true);
  bool _dirty = false;
  int _revision = 0;
  bool _readFailed = false;
  bool _disposed = false;
  String? lastError;
  UserBlockIndex(this._file);

  static String? normalizeUid(String? value) {
    if (value == null || !RegExp(r'^[0-9]+$').hasMatch(value.trim())) {
      return null;
    }
    final uid = int.tryParse(value.trim());
    return uid == null || uid <= 0 ? null : '$uid';
  }

  bool isBlocked(String? uid) => _entries.containsKey(normalizeUid(uid));
  List<BlockedUser> get entries => List.unmodifiable(
    _entries.values.toList()
      ..sort((a, b) => b.blockedAt.compareTo(a.blockedAt)),
  );
  Future<void> load() => _loading ??= _read();
  Future<void> attach(File? file) {
    _file = file;
    _readFailed = false;
    _loading = null;
    return load().then((_) async {
      if (_dirty) await flush();
    });
  }

  Future<void> _read() async {
    final file = _file;
    if (file == null) return;
    try {
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString());
      if (data is! Map || data['version'] != 1 || data['users'] is! List) {
        _readFailed = true;
        lastError = '黑名单读取失败，请稍后重试';
        if (!_disposed) notifyListeners();
        return;
      }
      for (final value in data['users'] as List) {
        if (value is! Map) continue;
        final uid = normalizeUid(value['uid']?.toString());
        final at = value['at'];
        if (uid == null || _overridden.contains(uid)) continue;
        _entries.putIfAbsent(
          uid,
          () => BlockedUser(
            uid: uid,
            name: value['name'] is String ? value['name'] : 'UID $uid',
            avatarUrl: value['avatar'] is String ? value['avatar'] : null,
            blockedAt: DateTime.fromMillisecondsSinceEpoch(at is int ? at : 0),
          ),
        );
      }
      if (!_disposed) notifyListeners();
    } catch (_) {
      _readFailed = true;
      lastError = '黑名单读取失败，请稍后重试';
      if (!_disposed) notifyListeners();
    }
  }

  Future<bool> block({
    required String uid,
    required String name,
    String? avatarUrl,
    String? currentUid,
    DateTime? blockedAt,
  }) async {
    final id = normalizeUid(uid);
    if (id == null || id == normalizeUid(currentUid)) {
      lastError = '无法拉黑这个用户';
      return false;
    }
    _overridden.add(id);
    _entries[id] = BlockedUser(
      uid: id,
      name: name.trim().isEmpty ? 'UID $id' : name.trim(),
      avatarUrl: avatarUrl,
      blockedAt: blockedAt ?? DateTime.now(),
    );
    _dirty = true;
    _revision++;
    if (!_disposed) notifyListeners();
    return flush();
  }

  Future<bool> unblock(String uid) async {
    final id = normalizeUid(uid);
    if (id == null) return false;
    _overridden.add(id);
    _entries.remove(id);
    _dirty = true;
    _revision++;
    if (!_disposed) notifyListeners();
    return flush();
  }

  Future<bool> flush() => _writes = _writes.then((_) async {
    await load();
    final file = _file;
    if (!_dirty || file == null) return true;
    if (_readFailed) {
      lastError = '黑名单未保存，请稍后重试';
      return false;
    }
    final revision = _revision;
    try {
      final payload = jsonEncode({
        'version': 1,
        'users': _entries.values
            .map(
              (e) => {
                'uid': e.uid,
                'name': e.name,
                'avatar': e.avatarUrl,
                'at': e.blockedAt.millisecondsSinceEpoch,
              },
            )
            .toList(),
      });
      await file.parent.create(recursive: true);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(payload, flush: true);
      await tmp.rename(file.path);
      if (revision == _revision) _dirty = false;
      lastError = null;
      return true;
    } catch (_) {
      lastError = '黑名单未保存，请稍后重试';
      return false;
    }
  });
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
