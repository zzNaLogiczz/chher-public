import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/animation.dart' show Cubic;
import 'package:flutter/painting.dart' show TextStyle;

import 'composer_tokens.dart';
import 'tokens.dart';

export 'voice_goo_tokens.dart';

/// Liquid and rim motion from composer-2026-11-26/index.html.
abstract final class VoiceTokens {
  static const barHeight = ComposerTokens.voiceHeight;
  static const heightGain = 3.0;
  static const capsuleSquash = .97;
  static const maxSpread = 1.08;
  static const maxOverhang = 8.0;
  static const spreadStiffness = 380.0;
  static const spreadDamping = 30.0;
  static const settleSpread = .002;
  static const settleVelocity = .01;
  static const settleVolume = .005;
  static const maxStep = 1 / 30;
  static const initialVolume = .06;
  static const volumeStiffness = 160.0;
  static const volumeDamping = 18.0;
  static const maxVolume = 1.0;
  static const maxEnvelope = 1.2;

  static const surfaceStep = 3.0;
  static const edgeFade = 26.0;
  static const baseAmplitude = 1.2;
  static const volumeAmplitude = 6.0;
  // The prototype uses angular wave numbers (roughly 140, 76 and 42 dp).
  static const surfaceWaves = [
    (weight: .5, frequency: .045, speed: -2.1, phase: 0.0),
    (weight: .32, frequency: .083, speed: 2.9, phase: 1.3),
    (weight: .18, frequency: .15, speed: -4.2, phase: 2.1),
  ];

  static const rippleWidth = 15.0;
  static const rippleDecay = 2.2;
  static const rippleLifetime = 1.6;
  static const rippleInset = 40.0;
  static const firstRippleAmplitude = 3.5;
  static const firstRippleSpeed = 240.0;
  static const accentRippleSpeed = 190.0;
  static const accentRippleBase = 1.2;
  static const accentRippleGain = 2.2;
  static const accentThreshold = .62;
  static const accentInterval = .34;
  static const volumeSampleInterval = .05;
  static const handsFreeRippleRange = 140.0;

  // Mulberry32, matching the prototype's rng().
  static const randomSeed = 0x6D2B79F5;
  static const randomStep = 0x6D2B79F5;
  static const randomMask = 0xFFFFFFFF;
  static const randomRange = 4294967296;
  static const randomSeedShift = 15;
  static const randomMixShift = 7;
  static const randomFinalShift = 14;
  static const randomMix = 61;

  static const liquidPeriod = 1.6;
  static const liquidSpeed = 34.0;
  static const liquidSpeedGain = 90.0;
  static const liquidStops = [0.0, .34, .67, 1.0];
  static const liquidFadeGain = 3.0;

  static const light = Color(0xFFFFFFFF);
  static const dark = Color(0xFF000000);
  static const shadeHeadroom = 10.0;
  static const shadeFade = .18;
  static const shadeStops = [
    0.0,
    shadeFade / (1 + shadeFade),
    (shadeFade + .42) / (1 + shadeFade),
    1.0,
  ];
  static const shadeTop = .22;
  static const shadeBottom = .1;
  static const sheenStops = [0.0, .16, .84, 1.0];
  static const sheenInset = 2.0;
  static const sheenTrim = 6.0;
  static const sheenDepth = 2.4;
  static const sheenMinLength = 14.0;
  static const sheenWidth = 1.4;
  static const sheenOpacity = .42;

  static const lineLabelGap = 14.0;
  static const lineInset = 24.0;
  static const lineMinLength = 24.0;
  static const lineCenterOffset = 1.0;
  static const lineAmplitudeInset = 9.0;
  static const lineAmplitudeBase = .9;
  static const lineStep = 4.0;
  static const lineSampleTolerance = .1;
  static const lineGlowWidth = 6.0;
  static const lineGlowOpacity = .14;
  static const lines = [
    (
      amplitude: 1.0,
      frequency: .05,
      speed: 3.2,
      phase: 0.0,
      opacity: .92,
      width: 1.7,
    ),
    (
      amplitude: .62,
      frequency: .072,
      speed: -2.5,
      phase: 1.7,
      opacity: .5,
      width: 1.2,
    ),
    (
      amplitude: .38,
      frequency: .11,
      speed: 4.3,
      phase: 3.1,
      opacity: .3,
      width: 1.0,
    ),
  ];

  static const timeWeight = FontWeight(650);
  static const hintWeight = FontWeight.w500;
  static const timeFeatures = [FontFeature.tabularFigures()];
  static const labelShadows = [
    Shadow(color: Color(0x1F000000), offset: Offset(0, 1), blurRadius: 6),
  ];
  static const labelsRevealAt = .85;
  static const labelsOpacity = .95;
  static const labelsIn = Duration(milliseconds: 150);
  static const toolsFade = Duration(milliseconds: 150);
  static const labelsOut = Duration(milliseconds: 70);
  static const hintIcon = 15.0;
  static const hintGap = 3.0;
  static const pullingHintDistance = 14.0;
  static const plainUndo = Duration(milliseconds: 160);
  static const silentStatus = Duration(milliseconds: 2400);
  static const redDismissSpread = .02;
  static const secondsPerMinute = 60;
  static const warningSecond = 50;
  static const countdownPop = Duration(milliseconds: 620);
  static const countdownCurve = Cubic(.3, 1.6, .5, 1);
  static const capacityFill = Color(0x33FFFFFF);
  static final capacityWarningFill = ComposerTokens.voiceTimeWarning.withValues(
    alpha: .32,
  );

  static String countdownLabel(int seconds) =>
      '还能说 ${secondsPerMinute - seconds} 秒';

  // The overhang and wave headroom keep the isolated painter's raster bounds
  // large enough for its overshoot and both initial ripple fronts.
  static const paintHeadroom =
      2 * firstRippleAmplitude + baseAmplitude + volumeAmplitude;
  static const tau = 2 * math.pi;
}

/// Composer-specific destructive liquid and drop label from the prototype.
abstract final class VoiceDropPaintTokens {
  static Color red(AppTokens t) =>
      t.isDark ? Radix.red11Dark : Radix.red11Light;
  static Color labelFill(AppTokens t) =>
      t.isDark ? const Color(0xFF3A1A19) : const Color(0xFFFDECEC);

  static const redStroke = 1.2;
  static const redStops = [0.0, .72, 1.0];
  static const glossCenter = Offset(.34, .30);
  static const glossRadius = .66;
  static const glossStops = [0.0, .42, 1.0];
  static const glossAlpha = [.55, .10, 0.0];
  static const glossMinSquash = .5;
  static const glossMinRadius = 7.0;
  static const sheenNeckGap = 12.0;
  static const footInset = 2.0;
  static const crossHalfSize = 5.5;
  static const crossStroke = 2.4;
  static const label = '松手撤销';
  static const labelFont = TextStyle(
    fontSize: 13.5,
    fontWeight: FontWeight(650),
  );
  static const labelHeight = 28.0;
  static const labelPadding = 12.0;
  static const labelInset = 10.0;
  static const labelLift = 10.0;
  static const labelMinScale = .6;
  static const labelPop = Duration(milliseconds: 420);
  static const labelCurve = Cubic(.3, 1.5, .5, 1);
}

/// Top-edge glow from `auraSVG`, `.aura` and the Composer animation loop.
abstract final class RimTokens {
  static const radius = ComposerTokens.panelRadius;
  static const top = 20.0;
  static const height = 70.0;
  static const legBottom = 40.0;
  static const stroke = 2.0;
  static const haloStroke = 9.0;
  static const haloSigma = 5.0;
  static const haloOpacity = .85;
  static const fadeStart = .55;
  static const fade = Duration(milliseconds: 300);
  static const cutFade = Duration(milliseconds: 150);
  static const fadeCurve = Cubic(.25, .1, .25, 1);
  static const period = 390.0;
  static const periodStops = [0.0, .25, .5, .75];
  static const speed = 100.0;
  static const volumeSpeed = 170.0;
  static const opacity = .30;
  static const volumeOpacity = .65;

  static List<Color> colors(AppTokens t) => [t.ai1, t.ai3, t.ai2, t.ai4];
}
