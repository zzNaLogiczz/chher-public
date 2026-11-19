import 'dart:math' as math;

abstract final class ListEndTokens {
  static const markerGap = 24.0;
  static const navigationGap = 16.0;

  /// Adjacent rows and cards can already contribute part of the marker gap.
  static double markerPadding(double existing) =>
      math.max(0, markerGap - existing);
}
