import 'dart:io';

import 'package:flutter/foundation.dart';

/// Serializes account changes and keeps each queued write tied to its own file.
abstract class AccountLocalIndex<S extends AccountIndexState>
    extends ChangeNotifier {
  AccountLocalIndex({required this._filename, this._directory, S? fixture})
    : _current = fixture,
      _currentUid = fixture == null ? null : '900',
      _uid = fixture == null ? null : '900';

  final String _filename;
  final Future<Directory?> Function()? _directory;
  final _unsaved = <String, S>{};
  Future<void> _switches = Future.value();
  S? _current;
  String? _currentUid;
  String? _uid;
  int? _identityRevision;
  int _epoch = 0;
  int _loadedEpoch = 0;
  bool _disposed = false;
  bool _legacyChecked = false;
  String? _legacyUid;

  String? get uid => _uid;
  int get epoch => _epoch;
  bool get accountReady => _loadedEpoch == _epoch;

  @protected
  S? get activeState => accountReady ? _current : null;
  String? get lastError => activeState?.lastError;

  static String? normalizeUid(String? value) {
    final text = value?.trim();
    if (text == null || !RegExp(r'^[0-9]+$').hasMatch(text)) return null;
    final uid = int.tryParse(text);
    return uid == null || uid <= 0 ? null : '$uid';
  }

  Future<void> setUid(String? uid, {int? identityRevision}) {
    final target = normalizeUid(uid);
    if (_uid == target && _identityRevision == identityRevision) {
      return accountReady ? Future.value() : _switches;
    }
    final pending = accountReady ? Future<void>.value() : _switches;
    _uid = target;
    _identityRevision = identityRevision;
    final epoch = ++_epoch;
    final switching = pending.then((_) async {
      final previous = _current;
      if (previous != null) {
        await _flush(previous);
        // Keep unsaved data associated with the original file after an I/O failure.
        if (previous.dirty) _unsaved[_currentUid!] = previous;
      }
      _current = null;
      _currentUid = target;
      if (target != null) {
        final state = _unsaved.remove(target) ?? await _open(target);
        _current = state;
        await _load(state);
      }
      if (!_disposed && epoch == _epoch) {
        _loadedEpoch = epoch;
        notifyListeners();
      }
    });
    _switches = switching;
    if (!_disposed) notifyListeners();
    return switching;
  }

  Future<S> _open(String uid) async {
    final dir = await _directory?.call();
    final file = dir == null ? null : File('${dir.path}/$uid/$_filename');
    final state = createState(file);
    if (file != null && !_legacyChecked && (_legacyUid ??= uid) == uid) {
      try {
        final legacy = File('${dir!.path}/$_filename');
        if (await legacy.exists()) {
          final skipped = File('${legacy.path}.migration-skipped');
          if (!await skipped.exists()) {
            if (await file.exists()) {
              // Preserve both files and prevent a later account claiming the legacy data.
              await skipped.create();
            } else {
              await file.parent.create(recursive: true);
              await legacy.rename(file.path);
            }
          }
        }
        _legacyChecked = true;
      } catch (_) {
        state.readFailed = true;
        state.lastError = readError;
      }
    }
    return state;
  }

  @protected
  S createState(File? file);

  @protected
  String get readError;

  @protected
  String get writeError;

  @protected
  Future<void> readFrom(S state, File file);

  @protected
  String encode(S state);

  Future<void> load() async {
    if (!accountReady) {
      final epoch = _epoch;
      await _switches;
      if (epoch != _epoch) return;
    }
    final state = activeState;
    if (state != null && !state.loaded) await _load(state);
  }

  Future<void> _load(S state) =>
      state.loading ??= _read(state).whenComplete(() => state.loaded = true);

  Future<void> _read(S state) async {
    final file = state.file;
    if (file == null || state.readFailed) return;
    try {
      if (!await file.exists()) return;
      await readFrom(state, file);
    } catch (_) {
      state.readFailed = true;
      state.lastError = readError;
    }
    if (!_disposed && identical(state, activeState)) notifyListeners();
  }

  @protected
  Future<bool> changed(S state) {
    state.dirty = true;
    state.revision++;
    if (!_disposed && identical(state, activeState)) notifyListeners();
    return _flush(state);
  }

  Future<bool> flush() async {
    if (!accountReady) {
      final epoch = _epoch;
      await _switches;
      if (epoch != _epoch) return true;
    }
    final state = activeState;
    return state == null ? true : _flush(state);
  }

  Future<bool> _flush(S state) {
    final pending = state.writes ?? Future.value(true);
    late final Future<bool> write;
    write = pending.then((_) => _write(state)).whenComplete(() {
      if (identical(state.writes, write)) state.writes = null;
    });
    return state.writes = write;
  }

  Future<bool> _write(S state) async {
    if (!state.loaded) await _load(state);
    final file = state.file;
    if (!state.dirty || file == null) return true;
    if (state.readFailed) {
      state.lastError = writeError;
      return false;
    }
    final revision = state.revision;
    try {
      final payload = encode(state);
      await file.parent.create(recursive: true);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(payload, flush: true);
      await tmp.rename(file.path);
      if (state.revision == revision) state.dirty = false;
      state.lastError = null;
      return true;
    } catch (_) {
      state.lastError = writeError;
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class AccountIndexState {
  AccountIndexState(this.file);

  final File? file;
  Future<void>? loading;
  bool loaded = false;
  Future<bool>? writes;
  bool dirty = false;
  bool readFailed = false;
  int revision = 0;
  String? lastError;
}
