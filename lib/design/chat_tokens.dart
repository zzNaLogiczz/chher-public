import 'package:flutter/material.dart';
import 'tokens.dart';

/// Confirmed conversation geometry; both palettes use semantic surface colors.
abstract final class ChatTokens {
  static const bubbleRadius = 20.0;
  static const joinedRadius = 6.0;
  static const avatar = 28.0;
  static const headerAvatar = 30.0;
  static const composerRadius = 26.0;
  static const listPadding = EdgeInsets.fromLTRB(
    AppSpace.screen,
    18,
    AppSpace.screen,
    24,
  );
  static const bodySize = 15.5;
  static const hold = Duration(milliseconds: 400);
  static const heldScale = .97;
  static const pendingAlpha = .55;
  static Color outgoingForeground(AppTokens t) => t.isDark ? t.bg : t.onAccent;
  static List<BoxShadow> bubbleShadow(AppTokens t) =>
      t.shadowE1.where((s) => s.blurRadius > 0).toList();
  static List<BoxShadow> composerShadow(AppTokens t) => [
    BoxShadow(
      color: t.isDark
          ? const Color(0xD9000000)
          : t.style == AppearanceStyle.misty
          ? const Color(0x3D000000)
          : const Color(0x4D3C1E19),
      offset: const Offset(0, -10),
      blurRadius: 30,
      spreadRadius: t.isDark ? -12 : -16,
    ),
  ];
  static Color menu(AppTokens t) => t.isDark ? t.fill : t.text;
  static Color menuText(AppTokens t) => t.isDark ? t.text : t.surface;
}
