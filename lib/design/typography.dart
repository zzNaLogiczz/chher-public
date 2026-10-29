/// 字号角色(规格 §5.2)。页面里只能引用角色名,颜色由调用处按令牌给。
library;

import 'package:flutter/painting.dart';

abstract final class AppType {
  static const largeTitle = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    height: 1.15,
    letterSpacing: -0.6,
  );
  static const title1 = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: -0.4,
  );
  static const title2 = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1.3,
  );
  static const headline = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );
  static const body = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w400,
    height: 1.6,
  );

  /// 阅读正文:行高放宽到 1.8
  static const reading = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w400,
    height: 1.8,
  );

  /// 阅读页「放大字号」开关打开后的正文
  static const readingLarge = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w400,
    height: 1.8,
  );
  static const callout = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.6,
  );
  static const subhead = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );
  static const footnote = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );
  static const caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  // 字号数值:给只接受 double 的 const 场景用,与上面的角色一一对应
  static const double sizeLargeTitle = 32;
  static const double sizeTitle1 = 26;
  static const double sizeTitle2 = 22;
  static const double sizeBody = 17;
  static const double sizeCallout = 16;
  static const double sizeSubhead = 15;
  static const double sizeFootnote = 13;
  static const double sizeCaption = 12;
}
