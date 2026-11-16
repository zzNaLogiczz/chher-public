import 'package:flutter/material.dart';
import 'tokens.dart';

/// Confirmed conversation geometry; both palettes use semantic surface colors.
abstract final class ChatTokens {
  static const bubbleRadius = 20.0;
  static const joinedRadius = 6.0;
  static const avatar = 28.0;
  static const headerAvatar = 30.0;
  static const composerRadius = 26.0;
  static const composerInset = 8.0;
  static const sendSize = 40.0;
  static const bodySize = 15.5;
  static const hold = Duration(milliseconds: 400);
  static const heldScale = .97;
  static const pendingAlpha = .55;
  static Color outgoingForeground(AppTokens t) => t.isDark ? t.bg : t.onAccent;
  static List<BoxShadow> bubbleShadow(AppTokens t) =>
      t.shadowE1.where((s) => s.blurRadius > 0).toList();
  static List<BoxShadow> composerShadow(AppTokens t) =>
      t.shadowE2.where((s) => s.blurRadius > 0).toList();
  static Color menu(AppTokens t) => t.isDark ? t.fill : t.text;
  static Color menuText(AppTokens t) => t.isDark ? t.text : t.surface;
}
