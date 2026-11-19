import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// Static body elements from the approved reading design.
abstract final class ContentElementTokens {
  static const panelRadius = 18.0;
  static const supplementTop = 24.0;
  static const supplementGap = 18.0;
  static const supplementHeadingGap = 6.0;
  static const supplementDateGap = 10.0;
  static const supplementIconSize = 14.0;
  static const supplementHeading = TextStyle(
    fontSize: 13,
    height: 1.4,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 650)],
  );
  static const supplementDate = TextStyle(
    fontSize: 13,
    height: 1.4,
    fontWeight: FontWeight.w500,
  );
  static const supplementBody = TextStyle(fontSize: 15.5, height: 1.7);
  static const replySupplementBody = TextStyle(fontSize: 14.5, height: 1.65);
  static const lockInset = EdgeInsets.fromLTRB(16, 18, 16, 16);
  static const headingSize = 13.0;
  static const metadataSize = 12.5;
  static const bodySize = 16.0;
  static const lockSize = 40.0;
  static const lockTitleSize = 15.0;
  static const buttonSize = 14.0;
  static const buttonHeight = 44.0;
  static const buttonRadius = 22.0;
  static const suppressedAvatarAlpha = .5;
  static Color panel(AppTokens t) => t.fill;
}
