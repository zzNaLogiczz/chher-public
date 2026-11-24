import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum AccountState { ok, expired, failed, unknown }

@immutable
class AccountSummary {
  const AccountSummary({
    required this.uid,
    required this.name,
    required this.state,
    required this.checkedAt,
    required this.notices,
    required this.messages,
    required this.lastUsedAt,
    this.failures = 0,
  });

  factory AccountSummary.fromMap(Map<Object?, Object?> map) => AccountSummary(
    uid: map['uid'] as String,
    name: map['name'] as String,
    state: AccountState.values.byName(map['state'] as String),
    checkedAt: map['checkedAt'] as int,
    notices: map['notices'] as int,
    messages: map['messages'] as int,
    lastUsedAt: map['lastUsedAt'] as int,
    failures: map['failures'] as int? ?? 0,
  );

  final String uid;
  final String name;
  final AccountState state;
  final int checkedAt;
  final int notices;
  final int messages;
  final int lastUsedAt;
  final int failures;
}

class AccountStore extends ChangeNotifier {
  static const _channel = MethodChannel('chh/accounts');

  List<AccountSummary> _accounts = const [];
  List<AccountSummary> get accounts => _accounts;
  String? _currentUid;
  String? get currentUid => _currentUid;
  int _max = 5;
  int get max => _max;
  bool get isFull => accounts.length >= max;
  String? _switchingUid;
  String? get switchingUid => _switchingUid;

  bool _listening = false;

  AccountSummary? find(String uid) =>
      _accounts.where((account) => account.uid == uid).firstOrNull;

  void setSwitchingUid(String? uid) {
    _switchingUid = uid;
    notifyListeners();
  }

  void start() {
    if (_listening ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') await reload();
    });
  }

  Future<void> reload() async {
    try {
      await _update('list');
    } on PlatformException {
      // Keep the last usable list until the next resume or change.
    }
  }

  Future<void> recover() async {
    try {
      await _update('recover').timeout(const Duration(seconds: 2));
    } on PlatformException {
      // CookieManager remains the session source if the vault is unavailable.
    } on TimeoutException {
      // Allow the app to finish startup.
    }
  }

  Future<bool> save(
    String uid,
    String name, {
    int? notices,
    int? messages,
    bool observed = false,
  }) => _update('save', {
    'uid': uid,
    'name': name,
    'notices': ?notices,
    'messages': ?messages,
    if (observed) 'observed': true,
  });

  Future<bool> activate(String uid) => _update('activate', {'uid': uid});
  Future<bool> remove(String uid) => _update('remove', {'uid': uid});
  Future<bool> beginLogin({String? reloginUid}) =>
      _update('beginLogin', {'uid': ?reloginUid});
  Future<bool> peekAuth() async => await _invoke<bool>('peekAuth') ?? false;
  Future<bool> endLogin({required bool restore}) =>
      _update('endLogin', {'restore': restore});
  Future<bool> markExpired(String uid) => _update('markExpired', {'uid': uid});
  Future<bool> check({List<String>? uids, bool force = false}) =>
      _update('check', {'uids': ?uids, 'force': force});

  Future<bool> _update(String method, [Map<String, Object>? args]) async {
    final list = await _invoke<Map<Object?, Object?>>(method, args);
    if (list == null) return false;
    _accounts = List.unmodifiable(
      (list['accounts'] as List).cast<Map<Object?, Object?>>().map(
        AccountSummary.fromMap,
      ),
    );
    _currentUid = list['currentUid'] as String?;
    _max = list['max'] as int;
    notifyListeners();
    return true;
  }

  Future<T?> _invoke<T>(String method, [Map<String, Object>? args]) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    }
  }

  @override
  void dispose() {
    if (_listening) _channel.setMethodCallHandler(null);
    super.dispose();
  }
}
