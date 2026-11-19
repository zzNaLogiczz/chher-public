import 'package:flutter/material.dart';

import 'tokens.dart';

abstract final class LinkCardTokens {
  static const radius = 20.0;
  static const compactRadius = 18.0;
  static const inset = 4.0;
  static const compactInset = 3.0;
  static const skeletonRadius = 6.0;
  static const marker = 44.0;
  static const compactMarker = 36.0;
  static const markerRadius = 12.0;
  static const compactMarkerRadius = 11.0;
  static const markerGap = 12.0;
  static const compactMarkerGap = 10.0;
  static const markerIconSize = 20.0;
  static const compactMarkerIconSize = 17.0;
  static const titleLines = 2;
  static const metadataGap = 4.0;
  static const authorDateGap = 10.0;
  static const chevronGap = 8.0;
  static const chevronSize = 14.0;
  static const skeletonTitleBarHeight = 13.0;
  static const skeletonDateBarHeight = 10.0;
  static const skeletonTitleWidths = [.78, .58];
  static const skeletonDateWidth = .38;
  static const title = TextStyle(
    fontSize: 15.5,
    height: 1.42,
    fontWeight: FontWeight.w600,
  );
  static const compactTitle = TextStyle(
    fontSize: 14.5,
    height: 1.42,
    fontWeight: FontWeight.w600,
  );
  static const metadata = TextStyle(fontSize: 12.5, height: 1.4);
  static const compactMetadata = TextStyle(fontSize: 12, height: 1.4);
  static const rowPadding = EdgeInsets.fromLTRB(10, 10, 12, 10);
  static const compactPadding = EdgeInsets.fromLTRB(8, 8, 10, 8);
  static List<BoxShadow> shadow(AppTokens t) =>
      t.shadowE1.where((s) => s.blurRadius > 0).toList();
  static Color skeleton(AppTokens t) => t.text3.withValues(alpha: .16);
  static Color externalUnderline(AppTokens t) =>
      t.accent.withValues(alpha: .35);
}
