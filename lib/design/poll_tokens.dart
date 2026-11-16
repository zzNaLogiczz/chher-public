import 'package:flutter/material.dart';
import 'tokens.dart';

abstract final class PollTokens {
  static const radius = 22.0, optionRadius = 18.0, wrapRadius = 14.0;
  static const padding = EdgeInsets.fromLTRB(14, 16, 14, 14);
  static const optionHeight = 36.0, gap = 6.0, mark = 18.0;
  static const markRadius = 5.5, markStroke = 1.5, pressScale = .98;
  static const disabledAlpha = .45, selectedAlpha = .09;
  static const iconBox = 28.0, icon = 16.0, titleGap = 8.0;
  static const optionsGap = 12.0, optionInset = 14.0, markInset = 9.0;
  static const wrapInset = 8.0, buttonInset = 20.0, buttonTouch = 44.0;
  static const chipHeight = 32.0, chipRadius = 16.0, voterHeight = 48.0;
  static const titleSize = 16.0, metaSize = 12.5, optionSize = 14.5;
  static const percentSize = 14.0, votesSize = 12.0, mineSize = 12.0;
  static const linkSize = 13.0, chipSize = 13.5, voterSize = 15.0;
  static const lineHeight = 1.4, minimumBar = .02;
  static const collapsedCount = 8;
  static Color bar(AppTokens t, bool dark, bool top) {
    final alpha = t.style == AppearanceStyle.misty
        ? (dark ? (top ? .24 : .13) : (top ? .18 : .10))
        : (dark ? (top ? .22 : .12) : (top ? .15 : .08));
    return t.accent.withValues(alpha: alpha);
  }

  static TextStyle text(
    double size,
    Color color, [
    FontWeight weight = FontWeight.w400,
  ]) => TextStyle(
    fontSize: size,
    color: color,
    fontWeight: weight,
    height: lineHeight,
  );
}
