import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../network/chh_session.dart';
import 'app_log.dart';
import 'chh_urls.dart';

/// Poll only a read-only header; opening a notice/PM list can mark it read.
/// Android owns notification permissions, persistent deduplication and taps.
class MessageNotifications with WidgetsBindingObserver {
  MessageNotifications(
    this.session, {
    this.interval = const Duration(minutes: 1),
  });

  final ChhSession session;
  final Duration interval;
  static const _channel = MethodChannel('chh/notifications');
  final openRequests = ValueNotifier<int>(0);
  Timer? _timer;
  bool _started = false;
  bool _foreground = true;
  bool _busy = false;
  int? _revision;
  int _generation = 0;
  Future<bool?>? _permissionRequest;

  void start() {
    if (_started) return;
    _started = true;
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openMessages') openRequests.value++;
    });
    session.addListener(_sessionChanged);
    _sessionChanged();
    unawaited(_consumeLaunch());
  }

  Future<void> _consumeLaunch() async {
    if (await _invoke<bool>('takeLaunch') == true && _started) {
      openRequests.value++;
    }
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
    if (!session.loggedIn) {
      final hadSession = _revision != null;
      _generation++;
      _revision = null;
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
      unawaited(_activate(_generation));
    }
    _publish();
  }

  void _publish() {
    final badges = session.badges;
    if (badges.uid != null) {
      unawaited(
        _invoke<void>('show', {
          'uid': badges.uid!,
          'notices': badges.notices,
          'messages': badges.messages,
        }),
      );
    }
  }

  Future<void> _activate(int generation) async {
    await (_permissionRequest ??= _invoke<bool>('requestPermission'));
    if (!_started || generation != _generation || !session.loggedIn) return;
    await _invoke<void>('setSession', {'active': true});
    if (!_started || generation != _generation || !session.loggedIn) return;
    _publish();
    _schedule();
    if (_foreground) unawaited(check());
  }

  void _schedule() {
    _timer?.cancel();
    _timer = _foreground && session.loggedIn
        ? Timer.periodic(interval, (_) => unawaited(check()))
        : null;
  }

  Future<void> check() async {
    if (!_started || !_foreground || !session.loggedIn || _busy) return;
    _busy = true;
    try {
      await session.client.getHtml(
        ChhUrls.forumIndex(),
        refresh: true,
        fallback: false,
      );
    } catch (error) {
      // Keep existing counters; retries wait for the next tick/resume.
      AppLog.w('NOTIFY', '检查未读失败 ${error.runtimeType}');
    } finally {
      _busy = false;
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
    WidgetsBinding.instance.removeObserver(this);
    _channel.setMethodCallHandler(null);
    openRequests.dispose();
  }
}
