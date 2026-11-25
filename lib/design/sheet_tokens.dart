import 'package:flutter/painting.dart';

/// Shared geometry and release thresholds for floating bottom panels.
abstract final class AppSheetTokens {
  static const inset = 8.0;
  static const radius = 40.0;
  static const dismissVelocity = 800.0;
  static const dismissFraction = .4;
}

abstract final class UserBlockSheetTokens {
  static const cardRadius = 20.0;
  static const name = TextStyle(fontSize: 20, fontWeight: FontWeight.w700);
}
