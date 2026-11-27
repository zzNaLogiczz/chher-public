/// Composer text and fly timing from composer-2026-11-26/index.html.
abstract final class VoiceTextTokens {
  static const riseDuration = .320;
  static const riseStagger = .028;
  static const riseHeight = .5;
  static const riseAccentStop = .55;
  static const riseCurve = (.2, .9, .25, 1.0);
  static const commitDuration = .240;
  static const commitStagger = .014;
  static const reducedFade = .150;
  static const cancelFade = .160;
  static const cutOpacity = .4;
  static const cursorWidth = 2.0;
  static const cursorHeight = 1.15;
  static const cursorGap = 1.0;
  static const cursorRadius = 1.0;
  static const cursorOpacity = .5;
  static const cursorVolumeGain = 1.4;

  static const flyGroups = 4;
  static const flyGroupStagger = .045;
  static const flyGlyphStagger = .007;
  static const flyDuration = .380;
  static const flyAcceleration = 2.2;
  static const flyLift = 20.0;
  static const flyBend = 24.0;
  static const flyBendRange = 36.0;
  static const flyRotationRange = 36.0;
  static const flyScaleLoss = .78;
  static const flyFadeStart = .72;
  static const flyPopDelay = .07;
  static const flyEmptyDelay = .05;
}
