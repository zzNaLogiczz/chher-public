import 'package:flutter/painting.dart';

/// Inline photo framing and the full-screen viewer's gesture thresholds.
abstract final class ImageTokens {
  static const darkTint = Color.from(alpha: 1, red: .92, green: .92, blue: .92);
  static const darkFilter = ColorFilter.mode(darkTint, BlendMode.modulate);
  static const viewerStatusThreshold = .5;

  static const radius = 16.0;
  static const dismissFraction = .4;
  static const dismissVelocity = 800.0;
  static const dismissScale = .25;
}
