/// App-scoped Android display preferences. These are hints, not guarantees.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract final class DisplayRefresh {
  static const channel = MethodChannel('chh/display_refresh');

  /// Native onResume/surfaceCreated also reapply this preference automatically.
  static Future<Map<String, Object?>> requestPreferred() =>
      _call('requestPreferred');
  static Future<Map<String, Object?>> read() => _call('read');

  static Future<Map<String, Object?>> _call(String method) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const {'available': false, 'reason': 'unsupported-platform'};
    }
    try {
      final result = await channel.invokeMapMethod<String, Object?>(method);
      return result ??
          const {'available': false, 'reason': 'empty-native-response'};
    } on MissingPluginException {
      return const {'available': false, 'reason': 'native-channel-unavailable'};
    } on PlatformException catch (error) {
      return {'available': false, 'reason': error.code};
    }
  }
}
