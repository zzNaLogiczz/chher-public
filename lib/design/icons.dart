/// 图标:界面统一使用 Solar 线条体(Outline),底栏保留实心体(Bold)
///
/// 规格 §5.6:顶栏、列表、工具栏、状态页用线条;底栏外观不变。
library;

import 'package:flutter/material.dart' show Icons;
import 'package:solar_icons/solar_icons.dart';

abstract final class AppIcons {
  static const sort = SolarIconsOutline.sortVertical;
  static const search = SolarIconsOutline.magnifier;
  static const comments = SolarIconsOutline.chatRoundDots;
  static const reply = SolarIconsOutline.chatSquareArrow;
  static const send = SolarIconsOutline.plain2;
  static const close = SolarIconsOutline.closeCircle;
  static const back = SolarIconsOutline.altArrowLeft;
  static const notification = SolarIconsOutline.bell;
  static const home = SolarIconsOutline.home2;
  static const forums = SolarIconsOutline.widget_5;
  static const person = SolarIconsOutline.userRounded;
  static const success = SolarIconsOutline.checkCircle;
  static const forward = SolarIconsOutline.altArrowRight;
  static const refresh = SolarIconsOutline.refresh;
  static const article = SolarIconsOutline.documentText;
  static const bookmark = SolarIconsOutline.bookmark;
  static const settings = SolarIconsOutline.settings;
  static const logout = SolarIconsOutline.logout;
  static const medal = SolarIconsOutline.medalStar;
  static const credits = SolarIconsOutline.walletMoney;
  static const log = SolarIconsOutline.document;
  static const update = SolarIconsOutline.downloadMinimalistic;
  static const compose = SolarIconsOutline.penNewSquare;
  static const lock = SolarIconsOutline.lock;
  static const views = SolarIconsOutline.eye;
  static const filter = SolarIconsOutline.filter;
  static const copy = SolarIconsOutline.copy;
  static const tag = SolarIconsOutline.hashtag;
  static const image = SolarIconsOutline.gallery;
  static const info = SolarIconsOutline.infoCircle;
  static const warning = SolarIconsOutline.dangerTriangle;
  static const more = SolarIconsOutline.menuDots;
  static const forbidden = SolarIconsOutline.forbidden;
  static const verified = SolarIconsOutline.shieldCheck;
  static const up = SolarIconsOutline.doubleAltArrowUp;
  static const down = SolarIconsOutline.altArrowDown;
  static const inbox = SolarIconsOutline.inbox;
  static const export = SolarIconsOutline.export;
  static const trash = SolarIconsOutline.trashBinMinimalistic;

  // 正文链接:离开 App 的链接、站内帖子卡片、视频播放
  static const externalLink = SolarIconsOutline.arrowRightUp;

  /// 原页面。Solar 字体里的地球类图标是坏字形(填成实心),用浏览器窗口表示网页
  static const webPage = SolarIconsOutline.windowFrame;
  static const thread = SolarIconsOutline.chatSquare;
  static const play = SolarIconsBold.play;

  /// 弹层右上角圆钮里的细叉(Solar 没有不带外框的叉)
  static const dismiss = Icons.close_rounded;

  // 底栏:外观不改,继续用实心体
  static const tabHome = SolarIconsBold.home2;
  static const tabForums = SolarIconsBold.widget_5;
  static const tabMessages = SolarIconsBold.chatRoundDots;
  static const tabMe = SolarIconsBold.userRounded;
}
