import 'package:flutter/material.dart';
import 'package:solar_icons/solar_icons.dart';

import 'tokens.dart';

/// Video screens keep the same dark, restrained brand tint in all four themes.
abstract final class ContentVideoTokens {
  static const aspectRatio = 16 / 9;
  static const radius = 16.0;
  static const compactRadius = 14.0;
  static const playSize = 58.0;
  static const playIconSize = 20.0;
  static const failureTravel = 6.0;
  static const foreground = Radix.whiteA12;
  static const browserText = Radix.slate12Light;
  static const television = SolarIconsOutline.tv;
  static final playFill = foreground.withValues(alpha: .16);
  static final label = foreground.withValues(alpha: .92);
  static const screen = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2B2427), Color(0xFF141112)],
  );
  static const pinkGlow = RadialGradient(
    center: Alignment(.7, -1),
    radius: .9,
    colors: [Color(0x38FB7299), Color(0x00FB7299)],
    stops: [0, .7],
  );
  static const blueGlow = RadialGradient(
    center: Alignment.bottomLeft,
    radius: .8,
    colors: [Color(0x1F00AEEC), Color(0x0000AEEC)],
    stops: [0, .7],
  );
  static final platformStyle = TextStyle(
    fontSize: 12.5,
    height: 1.5,
    fontWeight: FontWeight.w600,
    color: label,
  );
  static final identifierStyle = TextStyle(
    fontSize: 12.5,
    height: 1.5,
    color: foreground.withValues(alpha: .5),
  );
  static const failureStyle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );
  static const browserStyle = TextStyle(
    fontSize: 13.5,
    fontWeight: FontWeight.w600,
  );
}
