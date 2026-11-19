import 'package:flutter/widgets.dart';
import 'tokens.dart';

abstract final class ThreadTokens {
  static const authorAvatarGap = 12.0;
  static const authorTimeGap = 2.0;
  static const authorMoreSize = 36.0;
  static const authorMoreTarget = 44.0;
  static const authorMoreIconSize = 18.0;
  static const bodyTop = 20.0;
  static const imageBleed = 4.0;
  static const editThreshold = Duration(minutes: 10);
  static Color score(AppTokens t) =>
      t.isDark ? Radix.green11Dark : Radix.green11Light;
  static Color participants(AppTokens t) => Color.lerp(score(t), t.text3, .65)!;
}
