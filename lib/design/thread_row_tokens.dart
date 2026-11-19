import 'package:flutter/painting.dart';

import 'typography.dart';

abstract final class ThreadRowTokens {
  static const verticalPadding = 12.0;
  static const avatarSize = 16.0;
  static const iconSize = 14.0;
  static const gap = 6.0;
  static const iconGap = 3.0;
  static const separatorSize = 2.0;
  static const separatorInset = 4.0;
  static const summaryGap = 4.0;
  static const seenAvatarOpacity = 0.5;

  // Leave room for the identity and counts when a raw date is unusually long.
  static const timeWidthFraction = 0.40;
  static const countWidthFraction = 0.30;

  static const title = TextStyle(
    fontSize: 16.5,
    fontWeight: FontWeight.w600,
    height: 1.42,
  );
  static const summary = AppType.subhead;
  static const metadata = AppType.footnote;
  static const searchSummaryLines = 2;
  static const searchSkeletonRows = 3;
  static const searchSkeletonBarHeight = .62;
  static const searchSkeletonTitleWidth = .76;
  static const searchSkeletonSummaryWidths = [.9, .66];
  static const searchSkeletonMetadataWidth = .34;
}

abstract final class SearchInputTokens {
  static const progressSlot = 24.0;
}

abstract final class MyThreadTokens {
  static const replySnippetPadding = EdgeInsets.fromLTRB(12, 2, 4, 2);
}
