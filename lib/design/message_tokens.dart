import 'package:flutter/painting.dart';

import 'tokens.dart';

/// Approved message selector geometry and semantic colors.
abstract final class MessageTokens {
  static const segmentHeight = 44.0;
  static const segmentInset = 4.0;
  static const segmentRadius = 22.0;
  static const thumbRadius = 18.0;
  static const compactHeight = 34.0;
  static const compactWidth = 168.0;
  static const compactInset = 3.0;
  static const compactRadius = 17.0;
  static const compactThumbRadius = 14.0;
  static const unreadDot = 6.0;
  static const badgeGap = 6.0;
  static const swipeThreshold = 1 / 3;
  static const swipeVelocity = 500.0;
  static const overscrollLimit = .18;

  // Shared selectors outside messages retain their established palette.
  static Color standardTrack(AppTokens t, bool onLac) =>
      onLac ? const Color.fromRGBO(255, 248, 245, .18) : t.fill;
  static Color standardThumb(AppTokens t, bool onLac) => onLac
      ? const Color(0xFFFFF8F5)
      : t.isDark
      ? const Color(0xFF636366)
      : t.surface;
  static Color standardSelected(AppTokens t, bool onLac) =>
      onLac ? const Color(0xFF5A0E10) : t.text;
  static List<BoxShadow> standardShadow(AppTokens t, bool onLac) => onLac
      ? const [
          BoxShadow(
            color: Color(0x4D5A0508),
            offset: Offset(0, 1),
            blurRadius: 5,
          ),
        ]
      : t.shadowE1;

  static List<BoxShadow> thumbShadow(AppTokens t) =>
      t.shadowE1.where((shadow) => shadow.blurRadius > 0).toList();

  static Color track(AppTokens t, bool onLac) => onLac
      ? t.isDark
            ? t.scrim.withValues(alpha: .22)
            : t.lacBot.withValues(alpha: .16)
      : t.fill;
  static Color thumb(AppTokens t, bool onLac) => onLac
      ? t.onLac
      : t.isDark
      ? t.fill3
      : t.surface;
  static Color selected(AppTokens t, bool onLac) => onLac ? t.lacBot : t.text;
}
