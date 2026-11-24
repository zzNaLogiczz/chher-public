import 'package:flutter/painting.dart';

import 'typography.dart';

abstract final class SupportTokens {
  static const title = TextStyle(
    fontSize: 24,
    height: 1.38,
    fontWeight: FontWeight.w700,
    letterSpacing: -.2,
  );
  static final subtitle = AppType.subhead.copyWith(height: 1.6);
  static final action = AppType.callout.copyWith(fontWeight: FontWeight.w600);
  static const tapLimit = Duration(milliseconds: 350);
  static const impactInterval = Duration(milliseconds: 180);
  static const flash = Duration(milliseconds: 620);
}
