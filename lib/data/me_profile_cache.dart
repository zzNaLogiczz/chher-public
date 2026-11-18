import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/models.dart';

/// Only the last confirmed account's identity and displayed counters are kept.
class MeProfileCache extends ChangeNotifier {
  UserProfile? _value;
  String? _uid;
  bool _selected = false;
  File? _file;
  int _epoch = 0;
  Future<void> _writes = Future.value();

  UserProfile? forUser(String uid) => _value?.uid == uid ? _value : null;

  void select(String? uid) {
    if (_selected && _uid == uid && (_value == null || _value!.uid == uid)) {
      return;
    }
    _selected = true;
    final hadIdentity = _uid != null || _value != null;
    if (_uid != null || uid == null) _epoch++;
    _uid = uid;
    if (_value?.uid != uid) {
      _value = null;
      if (hadIdentity || uid == null) unawaited(flush());
    }
  }

  void put(UserProfile profile) {
    if (profile.uid != _uid) return;
    final previous = _value;
    _value = UserProfile(
      uid: profile.uid,
      name: profile.name,
      group: profile.group ?? previous?.group,
      groupId: profile.groupId ?? previous?.groupId,
      credits: profile.credits ?? previous?.credits,
      threads: profile.threads ?? previous?.threads,
      replies: profile.replies ?? previous?.replies,
    );
    unawaited(flush());
  }

  Future<void> attach(File file) async {
    _file = file;
    if (_value != null || (_selected && _uid == null)) {
      await flush();
      return;
    }
    final epoch = _epoch;
    try {
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (epoch != _epoch || _value != null || data['uid'] is! String) return;
      if (_selected && _uid != data['uid']) return;
      _value = UserProfile(
        uid: data['uid'] as String,
        name: data['name'] as String,
        group: data['group'] as String?,
        groupId: data['groupId'] as int?,
        credits: data['credits'] as int?,
        threads: data['threads'] as int?,
        replies: data['replies'] as int?,
      );
      notifyListeners();
    } catch (_) {
      // Missing, corrupt or reclaimed storage is a cold cache, never an error UI.
    }
  }

  Future<void> flush() => _writes = _writes.then((_) async {
    final file = _file;
    if (file == null) return;
    try {
      final profile = _value;
      if (profile == null) {
        if (await file.exists()) await file.delete();
      } else {
        final temporary = File('${file.path}.tmp');
        await temporary.writeAsString(
          jsonEncode({
            'uid': profile.uid,
            'name': profile.name,
            'group': profile.group,
            'groupId': profile.groupId,
            'credits': profile.credits,
            'threads': profile.threads,
            'replies': profile.replies,
          }),
        );
        await temporary.rename(file.path);
      }
    } catch (_) {
      // Preserve the in-memory snapshot when storage is unavailable.
    }
  });
}
