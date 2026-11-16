import 'package:flutter/painting.dart';

import 'typography.dart';

/// Approved avatar palette and name rules, shared across both appearance styles.
abstract final class AvatarTokens {
  static const colors = [
    Color(0xFFC9A27E),
    Color(0xFF8FA3B8),
    Color(0xFFA79BC4),
    Color(0xFF9DB59A),
    Color(0xFFC49A9A),
    Color(0xFFB8AE8F),
    Color(0xFF93B1B4),
    Color(0xFFB39C8E),
  ];
  static const foreground = Color(0xFFFFFFFF);
  static final _initial = RegExp(r'[一-龥A-Za-z0-9]');

  static String initial(String name) =>
      _initial.firstMatch(name)?.group(0)?.toUpperCase() ?? '?';

  static Color background(String name, {required bool dark}) {
    var hash = 0;
    // JS prototype iterates code points but hashes their first UTF-16 unit.
    for (final rune in name.runes) {
      final unit = rune > 0xFFFF ? 0xD800 + ((rune - 0x10000) >> 10) : rune;
      hash = (hash * 31 + unit) & 0xFFFFFFFF;
    }
    final color = colors[hash % colors.length];
    return dark
        ? Color.fromARGB(
            255,
            (color.r * 255 * .72).round(),
            (color.g * 255 * .72).round(),
            (color.b * 255 * .72).round(),
          )
        : color;
  }

  static TextStyle text(double size) => AppType.caption.copyWith(
    fontSize: (size * .4).clamp(AppType.sizeCaption, AppType.sizeTitle1),
    fontWeight: FontWeight.w700,
    color: foreground,
    height: 1,
  );
}
