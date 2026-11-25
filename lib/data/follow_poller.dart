import 'dart:async';

import '../models/models.dart';
import 'follow_index.dart';

/// Checks followed users in foreground rounds, with one request at a time.
class FollowPoller {
  FollowPoller({
    required this._index,
    required this._fetchThreads,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    _index.addListener(_schedule);
  }

  final FollowIndex _index;
  final Future<List<ThreadSummary>> Function(
    String uid,
    bool Function() shouldContinue,
  )
  _fetchThreads;
  final DateTime Function() _now;
  final _pending = <FollowedUser>[];
  final _checked = <String>{};
  Timer? _timer;
  DateTime? _roundStarted;
  Object? _forceOwner;
  Completer<void>? _roundCompletion;
  int? _sessionRevision;
  int _generation = 0;
  bool _active = false;
  bool _busy = false;
  bool _failed = false;
  bool _disposed = false;

  void update({
    required bool foreground,
    required bool loggedIn,
    required int sessionRevision,
  }) {
    if (_disposed) return;
    final active = foreground && loggedIn;
    if (active == _active && sessionRevision == _sessionRevision) return;
    if (sessionRevision != _sessionRevision ||
        (active && !_active && _failed)) {
      _failed = false;
      _roundStarted = null;
    }
    _active = active;
    _sessionRevision = sessionRevision;
    _stopRound();
    _schedule();
  }

  void _stopRound() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _pending.clear();
    _finishRound();
  }

  void _finishRound() {
    _checked.clear();
    _forceOwner = null;
    final completion = _roundCompletion;
    _roundCompletion = null;
    completion?.complete();
  }

  /// Starts or joins an immediate round. Only the latest caller can cancel it.
  /// All callers' futures complete when the round ends, including on failure
  /// or cancellation.
  ({void Function() cancel, Future<void> done})? forceCheck() {
    if (!_active) return null;
    final users = _index.all;
    if (users.isEmpty) return null;

    if (_checked.isEmpty && _pending.isEmpty) {
      _timer?.cancel();
      _timer = null;
      _failed = false;
      _roundStarted = _now();
    }
    // An in-progress scheduled round counts toward the same request budget.
    _pending
      ..clear()
      ..addAll(
        (users.toList()..sort(_byLastCheck))
            .where((user) => !_checked.contains(user.uid))
            .take(FollowIndex.maxChecksPerRound - _checked.length),
      );
    final owner = _forceOwner = Object();
    final completion = _roundCompletion ??= Completer<void>();
    if (!_busy && _timer == null) unawaited(_checkNext());
    return (
      cancel: () {
        if (!identical(owner, _forceOwner)) return;
        _stopRound();
        _schedule();
      },
      done: completion.future,
    );
  }

  void _schedule() {
    if (!_active ||
        _busy ||
        _failed ||
        _pending.isNotEmpty ||
        _checked.isNotEmpty) {
      return;
    }
    _timer?.cancel();
    _timer = null;
    final users = _index.all;
    if (users.isEmpty) return;

    final now = _now();
    final oldest = users
        .reduce((a, b) => _byLastCheck(a, b) <= 0 ? a : b)
        .lastCheck;
    final userDue = oldest?.add(FollowIndex.checkInterval) ?? now;
    final roundDue = _roundStarted?.add(FollowIndex.checkInterval) ?? now;
    final delay = (userDue.isAfter(roundDue) ? userDue : roundDue).difference(
      now,
    );
    _timer = Timer(delay, _startRound);
  }

  static int _byLastCheck(FollowedUser a, FollowedUser b) {
    final left = a.lastCheck;
    final right = b.lastCheck;
    if (left == right) return a.at.compareTo(b.at);
    if (left == null) return -1;
    if (right == null) return 1;
    return left.compareTo(right);
  }

  void _startRound() {
    _timer = null;
    final now = _now();
    final started = _roundStarted;
    if (started != null &&
        now.difference(started) < FollowIndex.checkInterval) {
      _schedule();
      return;
    }
    final due = _index.all.where((user) {
      final lastCheck = user.lastCheck;
      return lastCheck == null ||
          now.difference(lastCheck) >= FollowIndex.checkInterval;
    }).toList()..sort(_byLastCheck);
    if (due.isEmpty) {
      _schedule();
      return;
    }
    _roundStarted = now;
    _pending.addAll(due.take(FollowIndex.maxChecksPerRound));
    unawaited(_checkNext());
  }

  Future<void> _checkNext() async {
    _timer = null;
    while (_pending.isNotEmpty) {
      final user = _pending.removeAt(0);
      if (!_index.isFollowed(user.uid)) continue;

      _checked.add(user.uid);
      final generation = _generation;
      bool current() => _active && generation == _generation;
      _busy = true;
      try {
        final threads = await _fetchThreads(user.uid, current);
        if (current()) {
          await _index.recordThreadCheck(
            user,
            threads,
            at: _now(),
            shouldContinue: current,
          );
        }
      } catch (_) {
        if (current()) {
          _failed = true;
          _pending.clear();
        }
      } finally {
        _busy = false;
      }
      if (current() && _pending.isNotEmpty) {
        _timer = Timer(
          FollowIndex.betweenChecks,
          () => unawaited(_checkNext()),
        );
        return;
      }
    }
    _finishRound();
    _schedule();
  }

  void dispose() {
    _disposed = true;
    _active = false;
    _stopRound();
    _index.removeListener(_schedule);
  }
}
