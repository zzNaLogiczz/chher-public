/// 状态栏只绘制系统图标，背景由页面延伸到屏幕顶部。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

abstract final class AppSystemUi {
  static const lightIcons = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemStatusBarContrastEnforced: false,
  );

  static const darkIcons = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemStatusBarContrastEnforced: false,
  );

  static SystemUiOverlayStyle forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? lightIcons : darkIcons;
}
