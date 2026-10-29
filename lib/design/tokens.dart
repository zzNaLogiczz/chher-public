/// 设计令牌:颜色、层级、圆角、间距
///
/// 浅色与深色是同一套设计的两个主题,只换令牌,不换结构。
/// 规范见 docs/superpowers/specs/2026-10-27-ui-redesign-design.md §5。
library;

import 'package:flutter/material.dart';

/// Radix 原始色阶(只收本项目用到的步级,避免无用常量)
abstract final class Radix {
  static const whiteA12 = Color(0xFFFFFFFF);
  static const red11Light = Color(0xFFCE2C31);
  static const red11Dark = Color(0xFFFF9592);
  // slate
  static const slate1Light = Color(0xFFFCFCFD);
  static const slate2Light = Color(0xFFF9F9FB);
  static const slate3Light = Color(0xFFF0F0F3);
  static const slate4Light = Color(0xFFE8E8EC);
  static const slate5Light = Color(0xFFE0E1E6);
  static const slate6Light = Color(0xFFD9D9E0);
  static const slate10Light = Color(0xFF80838D);
  static const slate11Light = Color(0xFF60646C);
  static const slate12Light = Color(0xFF1C2024);

  static const slate1Dark = Color(0xFF111113);
  static const slate2Dark = Color(0xFF18191B);
  static const slate3Dark = Color(0xFF212225);
  static const slate4Dark = Color(0xFF272A2D);
  static const slate5Dark = Color(0xFF2E3135);
  static const slate6Dark = Color(0xFF363A3F);
  static const slate10Dark = Color(0xFF777B84);
  static const slate11Dark = Color(0xFFB0B4BA);
  static const slate12Dark = Color(0xFFEDEEF0);

  // blue
  static const blue3Light = Color(0xFFE6F4FE);
  static const blue9 = Color(0xFF0090FF);
  static const blue11Light = Color(0xFF0D74CE);
  static const blue3Dark = Color(0xFF0D2847);
  static const blue11Dark = Color(0xFF70B8FF);

  // amber
  static const amber3Light = Color(0xFFFFF7C2);
  static const amber6Light = Color(0xFFF3D673);
  static const amber11Light = Color(0xFFAB6400);
  static const amber3Dark = Color(0xFF302008);
  static const amber6Dark = Color(0xFF5C3D05);
  static const amber11Dark = Color(0xFFFFCA16);

  // green
  static const green3Light = Color(0xFFE6F6EB);
  static const green11Light = Color(0xFF218358);
  static const green3Dark = Color(0xFF132D21);
  static const green11Dark = Color(0xFF3DD68C);

  // violet
  static const violet3Light = Color(0xFFF4F0FE);
  static const violet11Light = Color(0xFF6550B9);
  static const violet3Dark = Color(0xFF291F43);
  static const violet11Dark = Color(0xFFBAA7FF);

  // bronze
  static const bronze3Light = Color(0xFFF6EDEA);
  static const bronze11Light = Color(0xFF7D5E54);
  static const bronze3Dark = Color(0xFF262220);
  static const bronze11Dark = Color(0xFFD4B3A5);

  // cyan
  static const cyan3Light = Color(0xFFDEF7F9);
  static const cyan11Light = Color(0xFF107D98);
  static const cyan3Dark = Color(0xFF082C36);
  static const cyan11Dark = Color(0xFF4CCCE6);

  // 红色只用于未读角标数字,取 Radix red 9
  static const red9 = Color(0xFFE5484D);
}

/// 全局设计令牌。通过 `AppTokens.of(context)` 取用。
///
/// 数值取自 docs/superpowers/specs/2026-10-27-ui-redesign-design.md §5.1–5.5。
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  // ---- 颜色:语义角色 ----
  final Color bg;
  final Color grouped;
  final Color surface;
  final Color fill;
  final Color fill2;
  final Color separator;
  final Color pressed;
  final Color text;
  final Color text2;
  final Color text3;
  final Color accent;
  final Color accentFill;
  final Color onAccent;
  final Color glass;
  final Color glassOnImage;
  final Color red;
  final Color green;
  final Color warn;
  final Color warnBg;
  final Color warnBorder;
  final Color scrim;

  const AppTokens({
    required this.bg,
    required this.grouped,
    required this.surface,
    required this.fill,
    required this.fill2,
    required this.separator,
    required this.pressed,
    required this.text,
    required this.text2,
    required this.text3,
    required this.accent,
    required this.accentFill,
    required this.onAccent,
    required this.glass,
    required this.glassOnImage,
    required this.red,
    required this.green,
    required this.warn,
    required this.warnBg,
    required this.warnBorder,
    required this.scrim,
  });

  static const AppTokens light = AppTokens(
    bg: Color(0xFFFFFFFF),
    grouped: Color(0xFFF2F2F7),
    surface: Color(0xFFFFFFFF),
    fill: Color.fromRGBO(118, 118, 128, .12),
    fill2: Color.fromRGBO(118, 118, 128, .22),
    separator: Color.fromRGBO(60, 60, 67, .16),
    pressed: Color(0xFFE5E5EA),
    text: Color(0xFF1C2024),
    text2: Color(0xFF6B6E76),
    text3: Color(0xFFA0A3AB),
    accent: Color(0xFF0D74CE),
    accentFill: Color.fromRGBO(13, 116, 206, .12),
    onAccent: Color(0xFFFFFFFF),
    glass: Color.fromRGBO(255, 255, 255, .92),
    glassOnImage: Color.fromRGBO(30, 30, 32, .50),
    red: Color(0xFFE5484D),
    green: Color(0xFF2B9A66),
    warn: Radix.amber11Light,
    warnBg: Radix.amber3Light,
    warnBorder: Radix.amber6Light,
    scrim: Color(0x6B1C2024),
  );

  static const AppTokens dark = AppTokens(
    bg: Color(0xFF0B0B0C),
    grouped: Color(0xFF0B0B0C),
    surface: Color(0xFF1C1C1E),
    fill: Color.fromRGBO(118, 118, 128, .24),
    fill2: Color.fromRGBO(118, 118, 128, .36),
    separator: Color.fromRGBO(84, 84, 88, .60),
    pressed: Color(0xFF2C2C2F),
    text: Color(0xFFEDEEF0),
    text2: Color(0xFFA1A4AB),
    text3: Color(0xFF6E7179),
    accent: Color(0xFF70B8FF),
    accentFill: Color.fromRGBO(112, 184, 255, .16),
    onAccent: Color(0xFF0B0B0C),
    glass: Color.fromRGBO(44, 44, 48, .92),
    glassOnImage: Color.fromRGBO(30, 30, 32, .50),
    red: Color(0xFFFF6369),
    green: Color(0xFF3DD68C),
    warn: Radix.amber11Dark,
    warnBg: Radix.amber3Dark,
    warnBorder: Radix.amber6Dark,
    scrim: Color(0x941C2024),
  );

  static AppTokens of(BuildContext context) =>
      Theme.of(context).extension<AppTokens>() ?? light;

  /// 页面底色:内容页用 bg,分组页用 grouped
  Color background(AppSurface s) => switch (s) {
    AppSurface.content => bg,
    AppSurface.grouped => grouped,
  };

  bool get isDark => bg.computeLuminance() < 0.3;

  // ---- 层级阴影(规格 §5.4) ----
  //
  // 0.5px 描边用 spreadRadius .5 / blurRadius 0 的阴影实现,
  // 这样描边和投影在同一个 boxShadow 里,圆角形状无需额外 border。

  /// e1:浮动圆钮、胶囊、分段滑块、阅读工具栏
  List<BoxShadow> get shadowE1 => [
    BoxShadow(
      color: isDark ? const Color(0x1AFFFFFF) : const Color(0x14000000),
      spreadRadius: .5,
      blurRadius: 0,
    ),
    BoxShadow(
      color: isDark ? const Color(0x80000000) : const Color(0x14000000),
      offset: const Offset(0, 2),
      blurRadius: 8,
    ),
  ];

  /// e2:精选大卡、横滑卡
  List<BoxShadow> get shadowE2 => isDark
      ? const [
          BoxShadow(color: Color(0x14FFFFFF), spreadRadius: .5, blurRadius: 0),
          BoxShadow(
            color: Color(0x99000000),
            offset: Offset(0, 10),
            blurRadius: 28,
          ),
        ]
      : const [
          BoxShadow(
            color: Color(0x0F000000),
            offset: Offset(0, 1),
            blurRadius: 3,
          ),
          BoxShadow(
            color: Color(0x1A000000),
            offset: Offset(0, 10),
            blurRadius: 28,
          ),
        ];

  @override
  AppTokens copyWith({
    Color? bg,
    Color? grouped,
    Color? surface,
    Color? fill,
    Color? fill2,
    Color? separator,
    Color? pressed,
    Color? text,
    Color? text2,
    Color? text3,
    Color? accent,
    Color? accentFill,
    Color? onAccent,
    Color? glass,
    Color? glassOnImage,
    Color? red,
    Color? green,
    Color? warn,
    Color? warnBg,
    Color? warnBorder,
    Color? scrim,
  }) {
    return AppTokens(
      bg: bg ?? this.bg,
      grouped: grouped ?? this.grouped,
      surface: surface ?? this.surface,
      fill: fill ?? this.fill,
      fill2: fill2 ?? this.fill2,
      separator: separator ?? this.separator,
      pressed: pressed ?? this.pressed,
      text: text ?? this.text,
      text2: text2 ?? this.text2,
      text3: text3 ?? this.text3,
      accent: accent ?? this.accent,
      accentFill: accentFill ?? this.accentFill,
      onAccent: onAccent ?? this.onAccent,
      glass: glass ?? this.glass,
      glassOnImage: glassOnImage ?? this.glassOnImage,
      red: red ?? this.red,
      green: green ?? this.green,
      warn: warn ?? this.warn,
      warnBg: warnBg ?? this.warnBg,
      warnBorder: warnBorder ?? this.warnBorder,
      scrim: scrim ?? this.scrim,
    );
  }

  /// 主题切换只在两套离散令牌之间跳,不做颜色插值
  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    return t < 0.5 ? this : other;
  }
}

/// 页面底色类型:内容页(白/近黑)与分组页(浅灰/近黑)
enum AppSurface { content, grouped }

/// 圆角令牌(规格 §5.3)。rFull 用 StadiumBorder / CircleBorder,不在此定义。
abstract final class AppRadii {
  /// 拖动条、细进度条这类 4–5dp 高的胶囊
  static const double bar = 2.5;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 18;
  static const double lg = 24;
  static const double xl = 28;
}

/// 间距令牌(规格 §5.5)
abstract final class AppSpace {
  static const double screen = 20;
  static const double groupInset = 16;
  static const double rowInset = 16;
  static const double section = 28;
  static const double hairline = 0.5;
}

/// 设置类行 30dp 图标底的色板,仅此一处使用彩色
abstract final class IconTints {
  static const blue = Color(0xFF0090FF);
  static const orange = Color(0xFFF76B15);
  static const green = Color(0xFF30A46C);
  static const violet = Color(0xFF8E4EC6);
  static const teal = Color(0xFF12A594);
  static const gray = Color(0xFF8B8D98);
}

/// 压在照片上的颜色:与主题无关,照片上永远是深色遮罩配浅色字
abstract final class ImageColors {
  static const foreground = Color(0xFFFCFCFD);
  static const shade = Color(0xFF1C2024);
  static const viewerBackground = Color(0xFF111113);
  static const viewerForeground = Color(0xFFEDEEF0);
}
