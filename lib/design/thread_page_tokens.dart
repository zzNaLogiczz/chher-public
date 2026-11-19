import 'motion.dart';
import 'list_end_tokens.dart';
import 'package:flutter/painting.dart';
import 'tokens.dart';

/// Page-level geometry from the approved thread V1/V3 prototype.
abstract final class ThreadPageTokens {
  static const titleSize = 24.0;
  static const titleHeight = 1.38;
  static const titleTracking = -.4;
  static const headingTop = 22.0;
  static const headingBottom = 6.0;
  static const eyebrowGap = 9.0;
  static const statsGap = 10.0;
  static const skeletonRadius = 7.0;
  static const skeletonLine = 14.0;
  static const skeletonTitleWidths = [.92, .63];
  static const skeletonAuthorWidths = [.44, .32];
  static const skeletonBodyWidths = [1.0, .91, .76];
  static const cardMargin = 16.0;
  static const cardRadius = 22.0;
  static const cardInset = 4.0;
  static const readingBarSize = 48.0;
  static const articleBarSize = 44.0;
  static const readingBarFadeHeight = ListEndTokens.markerGap;
  static const readingBarBottomPadding = 10.0;
  static const discussionBarBottomPadding = 8.0;
  static const readingBarTravel = 100.0;
  static const progressHeight = 2.0;
  static const commentHeadingGap = 8.0;
  static const commentHeadingBottom = 8.0;
  static const openingCommentsGap = 34.0;
  static const expansionLineWidth = 16.0;
  static const expansionLineHeight = 2.0;
  static const expansionHeight = 30.0;
  static const expansionLabel = TextStyle(
    fontSize: ThreadMetrics.metaSize,
    fontWeight: FontWeight.w600,
  );
  static const focusDuration = AppMotion.noticeHighlightDuration;
}
