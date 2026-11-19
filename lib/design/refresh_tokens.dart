/// Pull geometry follows the Chhers loading prototype. The threshold follows
/// the previous Material refresh gesture, as a fraction of the viewport.
abstract final class RefreshTokens {
  static const thresholdFraction = 1 / 6;
  static const armedExtent = 90.0;
  static const maxExtent = 120.0;
  static const holdExtent = 70.0;
}
