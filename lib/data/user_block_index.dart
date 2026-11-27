/// Device-local CHH user blocks; matching is always by stable UID.
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart' show StringCharacters;

import '../core/app_paths.dart';
import 'account_local_index.dart';

final UserBlockIndex userBlockIndex = UserBlockIndex(
  directory: () => AppPaths.instance.subdir('blocks'),
);

class BlockedUser {
  final String uid;
  final String name;
  final String? avatarUrl;
  final DateTime blockedAt;
  final String? note;
  final BlockedUserSource? src;
  const BlockedUser({
    required this.uid,
    required this.name,
    this.avatarUrl,
    required this.blockedAt,
    this.note,
    this.src,
  });
}

class BlockedUserSource {
  final int tid;
  final int pid;
  final int floor;
  final String title;
  final String excerpt;

  const BlockedUserSource({
    required this.tid,
    required this.pid,
    required this.floor,
    required this.title,
    required this.excerpt,
  });

  static BlockedUserSource? _fromJson(Object? value) => switch (value) {
    {
      'tid': final int tid,
      'pid': final int pid,
      'floor': final int floor,
      'title': final String title,
      'excerpt': final String excerpt,
    } =>
      BlockedUserSource(
        tid: tid,
        pid: pid,
        floor: floor,
        title: title,
        excerpt: excerpt,
      )._limited(),
    _ => null,
  };

  BlockedUserSource _limited() => BlockedUserSource(
    tid: tid,
    pid: pid,
    floor: floor,
    title: title,
    excerpt: excerpt.characters
        .take(UserBlockIndex.maxExcerptLength)
        .toString(),
  );

  Map<String, Object> _toJson() => {
    'tid': tid,
    'pid': pid,
    'floor': floor,
    'title': title,
    'excerpt': excerpt,
  };
}

class UserBlockIndexState extends AccountIndexState {
  UserBlockIndexState(super.file);

  final entries = <String, BlockedUser>{};
  final overridden = <String>{};
}

class UserBlockIndex extends AccountLocalIndex<UserBlockIndexState> {
  static const maxNoteLength = 200;
  static const maxExcerptLength = 100;

  UserBlockIndex({super.directory}) : super(filename: 'users-v1.json');

  UserBlockIndex.forTesting(File? file)
    : super(filename: 'users-v1.json', fixture: UserBlockIndexState(file));

  int _visibilityRevision = 0;
  int get visibilityRevision => _visibilityRevision;

  @override
  void notifyListeners() {
    _visibilityRevision++;
    super.notifyListeners();
  }

  @override
  UserBlockIndexState createState(File? file) => UserBlockIndexState(file);

  @override
  String get readError => '黑名单读取失败，请稍后重试';

  @override
  String get writeError => '黑名单未保存，请稍后重试';

  static String? normalizeUid(String? value) =>
      AccountLocalIndex.normalizeUid(value);

  static String? _normalizeNote(Object? value) {
    if (value is! String) return null;
    final note = value.characters.take(maxNoteLength).toString();
    return note.trim().isEmpty ? null : note;
  }

  bool isBlocked(String? uid) => entryFor(uid) != null;
  BlockedUser? entryFor(String? uid) => activeState?.entries[normalizeUid(uid)];
  Iterable<String> get blockedUids => activeState?.entries.keys ?? const [];
  List<BlockedUser> get entries => List.unmodifiable(
    (activeState?.entries.values.toList() ?? [])
      ..sort((a, b) => b.blockedAt.compareTo(a.blockedAt)),
  );

  @override
  Future<void> readFrom(UserBlockIndexState state, File file) async {
    final data = jsonDecode(await file.readAsString());
    if (data is! Map ||
        (data['version'] != 1 && data['version'] != 2) ||
        data['users'] is! List) {
      throw const FormatException('Invalid block index');
    }
    final legacy = data['version'] == 1;
    for (final value in data['users'] as List) {
      if (value is! Map) continue;
      final uid = normalizeUid(value['uid']?.toString());
      final at = value['at'];
      if (uid == null || state.overridden.contains(uid)) continue;
      state.entries.putIfAbsent(
        uid,
        () => BlockedUser(
          uid: uid,
          name: value['name'] is String ? value['name'] : 'UID $uid',
          avatarUrl: value['avatar'] is String ? value['avatar'] : null,
          blockedAt: DateTime.fromMillisecondsSinceEpoch(at is int ? at : 0),
          note: legacy ? null : _normalizeNote(value['note']),
          src: legacy ? null : BlockedUserSource._fromJson(value['src']),
        ),
      );
    }
    if (legacy) {
      state.dirty = true;
      state.revision++;
    }
  }

  Future<bool> block({
    required String uid,
    required String name,
    String? avatarUrl,
    String? currentUid,
    DateTime? blockedAt,
    String? note,
    BlockedUserSource? src,
  }) async {
    final started = epoch;
    if (activeState == null) await load();
    final state = activeState;
    if (started != epoch || state == null) return false;
    final id = normalizeUid(uid);
    if (id == null || id == this.uid || id == normalizeUid(currentUid)) {
      state.lastError = '无法拉黑这个用户';
      return false;
    }
    state.overridden.add(id);
    state.entries[id] = BlockedUser(
      uid: id,
      name: name.trim().isEmpty ? 'UID $id' : name.trim(),
      avatarUrl: avatarUrl,
      blockedAt: blockedAt ?? DateTime.now(),
      note: _normalizeNote(note),
      src: src?._limited(),
    );
    return changed(state);
  }

  Future<bool> updateNote(String uid, String? note) async {
    final started = epoch;
    await load();
    final state = activeState;
    if (started != epoch || state == null) return false;
    final entry = state.entries[normalizeUid(uid)];
    if (entry == null) return false;
    final normalized = _normalizeNote(note);
    if (entry.note == normalized) return flush();
    state.overridden.add(entry.uid);
    state.entries[entry.uid] = BlockedUser(
      uid: entry.uid,
      name: entry.name,
      avatarUrl: entry.avatarUrl,
      blockedAt: entry.blockedAt,
      note: normalized,
      src: entry.src,
    );
    return changed(state);
  }

  Future<bool> unblock(String uid) async {
    final started = epoch;
    if (activeState == null) await load();
    final state = activeState;
    if (started != epoch || state == null) return false;
    final id = normalizeUid(uid);
    if (id == null) return false;
    state.overridden.add(id);
    state.entries.remove(id);
    return changed(state);
  }

  @override
  String encode(UserBlockIndexState state) => jsonEncode({
    'version': 2,
    'users': state.entries.values
        .map(
          (e) => {
            'uid': e.uid,
            'name': e.name,
            'avatar': e.avatarUrl,
            'at': e.blockedAt.millisecondsSinceEpoch,
            'note': e.note,
            'src': e.src?._toJson(),
          },
        )
        .toList(),
  });
}
