import 'package:flutter/painting.dart';

import 'tokens.dart';
import 'typography.dart';

abstract final class EditorTokens {
  static const insets = EdgeInsets.fromLTRB(
    AppSpace.screen,
    24,
    AppSpace.screen,
    40,
  );
  static const destinationGap = 20.0;
  static const destination = TextStyle(fontSize: 14, height: 1.4);
  static const title = TextStyle(
    fontSize: AppType.sizeTitle2,
    fontWeight: FontWeight.w600,
    height: 1.45,
  );
  static const body = AppType.reading;
}
