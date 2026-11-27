import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'startup_idle.dart';

Future<void> warmPlatformTextActions() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

  await waitForStartupIdle();

  // Populate the Android channel's action-label cache after startup.
  await DefaultProcessTextService().queryTextActions();
}
