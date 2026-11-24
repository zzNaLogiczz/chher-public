import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../data/message_repository.dart';
import '../network/chh_session.dart';
import 'app_log.dart';
import 'chh_urls.dart';

enum NotificationAction { messages, relogin }

class NotificationOpenRequest {
  const NotificationOpenRequest(this.action, {this.uid});

  final NotificationAction action;
  final String? uid;

  static NotificationOpenRequest? fromPlatform(Object? value) {
    if (value is! Map) return null;
    final rawUid = value['uid'];
    if (rawUid != null && rawUid is! String) return null;
    final uid = rawUid is String && rawUid.isNotEmpty ? rawUid : null;
    return switch (value['action']) {
      'messages' => NotificationOpenRequest(
        NotificationAction.messages,
        uid: uid,
      ),
      'relogin' when uid != null => NotificationOpenRequest(
        NotificationAction.relogin,
        uid: uid,
      ),
      _ => null,
    };
  }
}

/// Poll the header and unread private conversation IDs.
/// Android owns notification permissions, persistent deduplication and taps.
class MessageNotifications with WidgetsBindingObserver {
  MessageNotifications(
    this.session, {
    this.interval = const Duration(seconds: 15),
  }) : _messages = MessageRepository(session.client);

  final ChhSession session;
  final MessageRepository _messages;
  final Duration interval;
  static const _channel = MethodChannel('chh/notifications');
  static const _pmSupplementInterval = Duration(seconds: 30);
  final openRequests = ValueNotifier<NotificationOpenRequest?>(null);
  Timer? _timer;
  bool _started = false;
  bool _foreground = true;
  bool _busy = false;
  bool _wasExpired = false;
  int _failures = 0;
  DateTime? _nextAttempt;
  int? _revision;
  int _generation = 0;
  int _pmReadSequence = 0;
  final _lastPmAttempts = <String?, DateTime>{};
  Future<bool?>? _permissionRequest;

  void start() {
    if (_started) return;
    _started = true;
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openNotification') _receiveOpen(call.arguments);
    });
    session.addListener(_sessionChanged);
    session.client.headerFreshness.addListener(_headerUpdated);
    _sessionChanged();
    unawaited(_consumeLaunch());
  }

  Future<void> _consumeLaunch() async {
    final launch = await _invoke<Object>('takeLaunch');
    if (_started) _receiveOpen(launch);
  }

  void _receiveOpen(Object? value) {
    final request = NotificationOpenRequest.fromPlatform(value);
    if (request != null) openRequests.value = request;
  }

  Future<T?> _invoke<T>(String method, [Map<String, Object>? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error) {
      AppLog.w('NOTIFY', '$method ${error.code}');
      return null;
    }
  }

  void _sessionChanged() {
    if (!_started) return;
    final recovered = _wasExpired && !session.currentExpired;
    _wasExpired = session.currentExpired;
    if (!session.loggedIn) {
      final hadSession = _revision != null;
      _generation++;
      _revision = null;
      _failures = 0;
      _nextAttempt = null;
      _timer?.cancel();
      _timer = null;
      if (hadSession) {
        unawaited(_invoke<void>('setSession', {'active': false}));
      }
      return;
    }
    if (_revision != session.identityRevision) {
      _revision = session.identityRevision;
      _generation++;
      _failures = 0;
      _nextAttempt = null;
      unawaited(_activate(_generation));
    } else if (recovered) {
      // A member header can arrive in the same clock tick as the guest header.
      _failures = 0;
      _nextAttempt = session.client.now().add(interval);
      _schedule();
    }
    _publish();
  }

  void _publish() {
    if (_busy || session.currentExpired) return;
    final badges = session.badges;
    if (badges.uid != null) {
      unawaited(
        _invoke<void>('show', {
          'uid': badges.uid!,
          'notices': badges.notices,
          'messages': badges.messages,
          'pmHasCount': session.pmHasCount,
        }),
      );
    }
  }

  Future<void> _activate(int generation) async {
    await _invoke<void>('setSession', {'active': true});
    if (!_started || generation != _generation || !session.loggedIn) return;
    _publish();
    _schedule();
    if (_foreground) unawaited(check());
    // The permission dialog must not block in-app unread counts.
    await (_permissionRequest ??= _invoke<bool>('requestPermission'));
    if (!_started || generation != _generation || !session.loggedIn) return;
    _publish();
  }

  void _headerUpdated() {
    if (session.client.lastFreshHeaderAt != null) {
      // Guest pages advance the response watermark but do not refresh the session.
      if (session.currentExpired) return;
      _failures = 0;
      _nextAttempt = null;
      if (!_busy &&
          _foreground &&
          session.loggedIn &&
          session.needsPmSupplement) {
        final last = _lastPmAttempts[_pmAccount];
        if (last == null ||
            session.client.now().difference(last) >= _pmSupplementInterval) {
          unawaited(_refreshUnreadPms());
        }
      }
    }
    _schedule();
  }

  String? get _pmAccount => session.badges.uid ?? session.accounts?.currentUid;

  Future<void> _refreshUnreadPms() async {
    final account = _pmAccount;
    _lastPmAttempts[account] = session.client.now();
    final generation = _generation;
    final cacheGeneration = session.client.cacheGeneration;
    final revision = session.pmRevision;
    final sequence = ++_pmReadSequence;
    final ids = await _messages.unreadPmIds();
    if (_started &&
        generation == _generation &&
        cacheGeneration == session.client.cacheGeneration &&
        sequence == _pmReadSequence &&
        account == _pmAccount &&
        !session.currentExpired &&
        revision == session.pmRevision) {
      session.setUnreadPmIds(ids);
    }
  }

  Duration get _pollDelay {
    final delay = interval * (1 << _failures);
    return _failures > 0 && delay > const Duration(minutes: 5)
        ? const Duration(minutes: 5)
        : delay;
  }

  void _schedule() {
    _timer?.cancel();
    _timer = null;
    if (!_started || !_foreground || !session.loggedIn || _busy) return;
    final now = session.client.now();
    final due =
        _nextAttempt ??
        session.client.lastFreshHeaderAt?.add(interval) ??
        now.add(interval);
    final remaining = due.difference(now);
    // A wall-clock rollback must not extend a relative polling/backoff interval.
    final delay = remaining.isNegative
        ? Duration.zero
        : remaining > _pollDelay
        ? _pollDelay
        : remaining;
    _timer = Timer(delay, () {
      final last = session.client.lastFreshHeaderAt;
      final age = last == null ? null : session.client.now().difference(last);
      if (!session.currentExpired &&
          age != null &&
          !age.isNegative &&
          age < interval) {
        _schedule();
      } else {
        unawaited(check());
      }
    });
  }

  /// Explicit checks and resume bypass freshness/backoff; timer reads are deferred
  /// by a real network header, including one whose unread counts did not change.
  Future<void> check() async {
    if (!_started || !_foreground || !session.loggedIn || _busy) return;
    _busy = true;
    _timer?.cancel();
    final generation = _generation;
    final cacheGeneration = session.client.cacheGeneration;
    final authentication = session.authenticationRevision;
    final headerRevision = session.client.freshHeaderRevision;
    var readHeader = false;
    try {
      await session.client.getHtml(
        ChhUrls.forumIndex(),
        refresh: true,
        fallback: false,
      );
      readHeader =
          _started &&
          authentication == session.authenticationRevision &&
          cacheGeneration == session.client.cacheGeneration &&
          !session.currentExpired &&
          session.client.freshHeaderRevision != headerRevision;
      if (readHeader) await _refreshUnreadPms();
    } catch (error) {
      AppLog.w('NOTIFY', '检查未读失败 ${error.runtimeType}');
    } finally {
      _busy = false;
      if (_started &&
          (generation == _generation ||
              (readHeader &&
                  authentication == session.authenticationRevision))) {
        final failed =
            session.currentExpired ||
            session.client.freshHeaderRevision == headerRevision;
        _failures = failed ? (_failures + 1).clamp(0, 5) : 0;
        _nextAttempt = failed ? session.client.now().add(_pollDelay) : null;
      }
      if (_started &&
          readHeader &&
          authentication == session.authenticationRevision &&
          cacheGeneration == session.client.cacheGeneration) {
        _publish();
      }
      _schedule();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _schedule();
    if (_foreground) unawaited(check());
  }

  void dispose() {
    _started = false;
    _generation++;
    _timer?.cancel();
    session.removeListener(_sessionChanged);
    session.client.headerFreshness.removeListener(_headerUpdated);
    WidgetsBinding.instance.removeObserver(this);
    _channel.setMethodCallHandler(null);
    openRequests.dispose();
  }
}
