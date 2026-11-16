import 'package:flutter/painting.dart';

import 'typography.dart';

/// Approved directory and forum list dimensions.
abstract final class ForumTokens {
  static const groupRadius = 22.0;
  static const groupInset = 4.0;
  static const rowRadius = 18.0;
  static const filterHeight = 48.0;
  static const filterRadius = 16.0;
  static const fabTravel = 100.0;
  static const activityDot = 5.0;
  static const avatarSize = 18.0;
  static const countWidth = 44.0;
  static const badgeRadius = 8.0;
  static const seenAvatarOpacity = .5;
  static const title = TextStyle(
    fontSize: 16.5,
    fontWeight: FontWeight.w600,
    height: 1.42,
  );
  static const metadata = AppType.footnote;
}
