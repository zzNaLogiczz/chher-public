import 'package:flutter/widgets.dart';

/// 正文引用定稿；正文尺寸可由 ReadingMetrics 覆盖。
abstract final class QuoteTokens {
  static const radius = 16.0;
  static const padding = EdgeInsets.fromLTRB(14, 11, 14, 12);
  static const collapsedLines = 4;
  static const gap = 4.0;
  static const actionHeight = 44.0;
  static const fadeHeight = 24.0;
  static const body = TextStyle(fontSize: 15, height: 1.65);
  static const author = TextStyle(fontSize: 13, fontWeight: FontWeight.w600);
  static const reference = TextStyle(fontSize: 12, fontWeight: FontWeight.w600);
  static const mark = TextStyle(fontSize: 22, height: 1, fontFamily: 'Georgia');
}
