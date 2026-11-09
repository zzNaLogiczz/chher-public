/// Account- and target-scoped drafts. Tokens and cookies are never persisted.
library;

import 'dart:convert';
import 'dart:io';

import '../core/app_paths.dart';

class PostInteractionDraft {
  final String text;
  final Map<String, int> scores;
  final String reason;
  final bool notify;
  final bool uncertain;
  const PostInteractionDraft({
    this.text = '',
    this.scores = const {},
    this.reason = '',
    this.notify = false,
    this.uncertain = false,
  });
  Map<String, Object> toJson() => {
    'text': text,
    'scores': scores,
    'reason': reason,
    'notify': notify,
    'uncertain': uncertain,
  };
}

final postInteractionDrafts = PostInteractionDraftStore(
  resolveFile: () async {
    final dir = await AppPaths.instance.subdir('interactions');
    return dir == null ? null : File('${dir.path}/drafts-v1.json');
  },
  requireDurability: true,
);

class PostInteractionDraftStore {
  File? _file;
  bool _readFailed = false;
  final Future<File?> Function()? resolveFile;
  final bool requireDurability;
  final _values = <String, PostInteractionDraft>{};
  final _touched = <String>{};
  Future<void>? _loading;
  Future<void> _writes = Future<void>.value();
  PostInteractionDraftStore({
    this._file,
    this.resolveFile,
    this.requireDurability = false,
  });

  static String key(String actor, int tid, int pid, String kind) =>
      jsonEncode([actor, tid, pid, kind]);
  PostInteractionDraft? get(String key) => _values[key];
  Future<void> load() => _loading ??= _read();
  Future<void> _read() async {
    try {
      _file ??= await resolveFile?.call();
      final file = _file;
      if (file == null || !await file.exists()) return;
      final root = jsonDecode(await file.readAsString());
      if (root is! Map || root['version'] != 1 || root['drafts'] is! Map) {
        _readFailed = true;
        return;
      }
      for (final e in (root['drafts'] as Map).entries) {
        if (e.key is! String || _touched.contains(e.key) || e.value is! Map) {
          continue;
        }
        final v = e.value as Map;
        final scores = <String, int>{};
        if (v['scores'] is Map) {
          for (final s in (v['scores'] as Map).entries) {
            if (s.key is String && s.value is int) scores[s.key] = s.value;
          }
        }
        _values[e.key] = PostInteractionDraft(
          text: v['text'] is String ? v['text'] : '',
          scores: scores,
          reason: v['reason'] is String ? v['reason'] : '',
          notify: v['notify'] == true,
          uncertain: v['uncertain'] == true,
        );
      }
    } catch (_) {
      _readFailed = true;
    }
  }

  Future<bool> put(String key, PostInteractionDraft value) async {
    _touched.add(key);
    _values[key] = value;
    await load();
    return _save();
  }

  Future<bool> remove(String key) async {
    _touched.add(key);
    _values.remove(key);
    await load();
    return _save();
  }

  Future<bool> _save() async {
    if (_readFailed && requireDurability) return false;
    var ok = true;
    final snapshot = jsonEncode({
      'version': 1,
      'drafts': {for (final e in _values.entries) e.key: e.value.toJson()},
    });
    _writes = _writes.then((_) async {
      final file = _file;
      if (file == null) {
        ok = !requireDurability;
        return;
      }
      try {
        await file.parent.create(recursive: true);
        final temp = File('${file.path}.tmp');
        await temp.writeAsString(snapshot, flush: true);
        await temp.rename(file.path);
      } catch (_) {
        ok = false;
      }
    });
    await _writes;
    return ok;
  }
}
