import 'package:flutter/material.dart';

import 'tokens.dart';

/// The fixed paper frame and its photo treatment, shared by both styles.
abstract final class ImageStackTokens {
  static const collapseFill = Radix.slate12Light;
  static const fallbackAspectRatio = 4 / 3;
  static const captionHeight = 52.0;
  static const deckFoot = 16.0;
  static const travelExtra = 70.0;
  static const collapseGap = 12.0;
  static const glowInset = 18.0;
  static const glowBlur = 40.0;
  static const glowSpread = -14.0;
  static const glowOffset = Offset(0, 22);
  static const glowOpacity = .25;
  static const frameHeight = 480.0;
  static const compactFrameHeight = 300.0;
  static const minFrameHeight = 200.0;
  static const compactMinFrameHeight = 150.0;
  static const paperRadius = 22.0;
  static const compactPaperRadius = 18.0;
  static const border = 6.0;
  static const compactBorder = 5.0;
  static const wellRadius = 16.0;
  static const compactWellRadius = 13.0;
  static const photoRadius = 8.0;
  static const matInset = 12.0;
  static const photoLift = 8.0;
  static const expandedRadius = 16.0;
  static const gap = 10.0;
  static const paperOffsets = [7.0, 13.0];
  static const paperInsets = [22.0, 46.0];
  static const paperRotations = [-1.0, 1.2];
  static const swipeFraction = .3;
  static const swipeVelocity = 450.0;
  static const rotationPerPixel = .035;
  static const hintDistance = 16.0;
  static const incomingScale = .965;
  static const incomingDim = .12;
  static const fillTolerance = .04;
  static const longRatio = .4;
  static const longFrameRatio = .5;
  static const sampleSize = 48;
  static const blurSigma = 40.0;
  static const saturation = 1.45;
  static const atmosphereCacheSize = 96;
  static const ink = Color(0xFF000000);
  static const clear = Color(0x00000000);
  static const onImage = Radix.whiteA12;
  static const longLabelHeight = 72.0;

  static List<BoxShadow> glowShadow(Color color, double strength) => [
    BoxShadow(
      color: color.withValues(alpha: strength * glowOpacity),
      blurRadius: glowBlur,
      spreadRadius: glowSpread,
      offset: glowOffset,
    ),
  ];
  static List<BoxShadow> edgeShadow(double opacity) => [
    for (final shadow in paperShadow)
      shadow.copyWith(
        color: shadow.color.withValues(alpha: shadow.color.a * opacity),
      ),
  ];
  static Color paper(AppTokens t) => t.isDark ? t.surface : Radix.whiteA12;
  static Color mist(AppTokens t) =>
      (t.isDark ? ink : Radix.whiteA12).withValues(alpha: t.isDark ? .62 : .64);
  static const photoShadow = [
    BoxShadow(color: Color(0x18000000), blurRadius: 5, offset: Offset(0, 2)),
  ];
  static const paperShadow = [
    BoxShadow(color: Color(0x14000000), blurRadius: 3, offset: Offset(0, 1)),
  ];
  static const frontShadow = [
    BoxShadow(color: Color(0x26000000), blurRadius: 16, offset: Offset(0, 8)),
  ];
  static const liftShadow = [
    BoxShadow(color: Color(0x38000000), blurRadius: 28, offset: Offset(0, 18)),
  ];
}
