/// 设计令牌:颜色、层级、圆角、间距
///
/// 浅色与深色是同一套设计的两个主题,只换令牌,不换结构。
/// 红色主题(朱漆红 v2)令牌对应 design-prototypes/red-theme-2026-11-10
/// 的 lacquer 方案:漆面(lac*)只给一级页,纸面沿用暖纸基底。
library;

import 'package:flutter/material.dart';

/// 界面风格:与明暗正交的第四象限。
///
/// - cinnabar(朱砂红):1.0.8 起的漆面设计,一级页用 LacScaffold。
/// - misty(薄雾白):1.0.7 的纸面设计,一级页用 LargeTitleScaffold。
///
/// 两风格共用同一套组件与令牌结构;薄雾白组里漆面相关令牌给纸面
/// 退化值(壳不消费它们),色阶常量是 1.0.7 原值(部分 Radix 步级
/// 在 v2 改过值,不能直接引用现常量)。
enum AppearanceStyle {
  misty('薄雾白'),
  cinnabar('朱砂红');

  final String label;
  const AppearanceStyle(this.label);
}

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

  // amber
  static const amber3Light = Color(0xFFFDF2DD);
  static const amber6Light = Color(0xFFF3D673);
  static const amber11Light = Color(0xFF8E5D1E);
  static const amber3Dark = Color(0xFF32230E);
  static const amber6Dark = Color(0xFF5C3D05);
  static const amber11Dark = Color(0xFFE3B667);

  // green
  static const green3Light = Color(0xFFDFF5E7);
  static const green11Light = Color(0xFF337C56);
  static const green3Dark = Color(0xFF153524);
  static const green11Dark = Color(0xFF69C090);

  // 红色只用于未读角标数字,取主题红(与品牌红同源,语义唯一)
  static const badgeLight = Color(0xFFCA3131);
  static const badgeDark = Color(0xFFCE3A39);
}

/// 全局设计令牌。通过 `AppTokens.of(context)` 取用。
///
/// 朱漆红 v2:暖纸基底 + 漆面(lacquer)覆盖层,数值取自
/// design-prototypes/red-theme-2026-11-10/style.css 的 lacquer 方案。
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  /// 所属界面风格;壳(LacScaffold/LargeTitleScaffold)按它分支,
  /// 组件不需要单独感知风格。
  final AppearanceStyle style;

  // ---- 颜色:语义角色 ----
  final Color bg;
  final Color grouped;
  final Color surface;
  final Color fill;
  final Color fill2;
  final Color fill3;
  final Color greenSoft;
  final Color greenFill;
  final Color greenLine;
  final Color separator;
  final Color pressed;
  final Color text;
  final Color text2;
  final Color text3;
  final Color accent;
  final Color accentFill;
  final Color accentFill2;
  final Color accentLine;
  final Color onAccent;
  final Color glass;
  final Color glassOnImage;

  /// 画框留白的磨砂雾面(叠在模糊氛围层上)
  final Color frostedMist;
  final Color red;
  final Color green;
  final Color warn;
  final Color warnBg;
  final Color warnBorder;
  final Color scrim;

  // ---- 朱漆红 v2 新增:漆面与色阶 ----

  /// 漆面渐变三档(一级页顶栏、启动页;168° 渐变在竖屏下近似竖向)
  final Color lacTop;
  final Color lacMid;
  final Color lacBot;

  /// 漆面上的文字:奶白 / 淡朱 / 半透明奶白
  final Color onLac;
  final Color onLac2;
  final Color onLac3;

  /// 色(chip)底与字:版块签、楼主签、评分按钮底
  final Color chipBg;
  final Color chipText;

  /// 未读整行底(朱 50,浅色读作暖纸不是粉)
  final Color unreadBg;

  /// 实心选中底与评分角签底
  final Color scoreBg;

  /// 实心红按钮的漆面渐变两档(发送、发帖 FAB 等)
  final Color btnTop;
  final Color btnBot;

  /// 正文链接下划线的浅朱(v1 规则:正文文字不变红,只换下划线)
  final Color linkLine;

  /// 国色线形图标组:仅用于图标,不引入新的界面色相
  final Color tintZhu;
  final Color tintDai;
  final Color tintTan;
  final Color tintZhe;
  final Color tintCi;
  final Color tintMo;

  const AppTokens({
    required this.style,
    required this.bg,
    required this.grouped,
    required this.surface,
    required this.fill,
    required this.fill2,
    required this.fill3,
    required this.greenSoft,
    required this.greenFill,
    required this.greenLine,
    required this.separator,
    required this.pressed,
    required this.text,
    required this.text2,
    required this.text3,
    required this.accent,
    required this.accentFill,
    required this.accentFill2,
    required this.accentLine,
    required this.onAccent,
    required this.glass,
    required this.glassOnImage,
    required this.frostedMist,
    required this.red,
    required this.green,
    required this.warn,
    required this.warnBg,
    required this.warnBorder,
    required this.scrim,
    required this.lacTop,
    required this.lacMid,
    required this.lacBot,
    required this.onLac,
    required this.onLac2,
    required this.onLac3,
    required this.chipBg,
    required this.chipText,
    required this.unreadBg,
    required this.scoreBg,
    required this.btnTop,
    required this.btnBot,
    required this.linkLine,
    required this.tintZhu,
    required this.tintDai,
    required this.tintTan,
    required this.tintZhe,
    required this.tintCi,
    required this.tintMo,
  });

  /// 朱砂红 · 浅色(1.0.8 定稿值)
  static const AppTokens cinnabarLight = AppTokens(
    style: AppearanceStyle.cinnabar,
    // 暖纸基底(v2 从冷灰换成暖调,色相与漆面同带)
    bg: Color(0xFFFFFDFC),
    grouped: Color(0xFFF6F3F1),
    surface: Color(0xFFFFFFFE),
    fill: Color.fromRGBO(120, 104, 100, .12),
    fill2: Color.fromRGBO(120, 104, 100, .22),
    fill3: Color.fromRGBO(120, 104, 100, .06),
    greenSoft: Color.fromRGBO(51, 124, 86, .09),
    greenFill: Radix.green3Light,
    greenLine: Color.fromRGBO(51, 124, 86, .16),
    separator: Color.fromRGBO(70, 40, 34, .14),
    pressed: Color(0xFFEDE8E6),
    text: Color(0xFF201A19),
    text2: Color(0xFF6E6563),
    text3: Color(0xFF9E9694),
    // 朱 700:红字主用色(纸上 6.78:1)
    accent: Color(0xFFAF2025),
    accentFill: Color(0xFFFFE8E2),
    accentFill2: Color(0xFFFFD4CC),
    accentLine: Color(0xFFFDB6AB),
    onAccent: Color(0xFFFFFFFF),
    glass: Color.fromRGBO(255, 253, 252, .92),
    glassOnImage: Color.fromRGBO(30, 30, 32, .50),
    frostedMist: Color.fromRGBO(255, 253, 252, .38),
    // 破坏性与品牌同一种红:语义唯一
    red: Color(0xFFAF2025),
    green: Color(0xFF337C56),
    warn: Radix.amber11Light,
    warnBg: Radix.amber3Light,
    warnBorder: Color(0xFFF2DDB0),
    scrim: Color.fromRGBO(32, 20, 18, .36),
    // 漆面渐变 #C62F2F → #94151E
    lacTop: Color(0xFFC62F2F),
    lacMid: Color(0xFFAF2025),
    lacBot: Color(0xFF94151E),
    onLac: Color(0xFFFFF8F5),
    onLac2: Color(0xFFF9E2DA),
    onLac3: Color.fromRGBO(255, 248, 245, .62),
    chipBg: Color(0xFFFFE8E2),
    chipText: Color(0xFF8A161B),
    unreadBg: Color(0xFFFFF4F1),
    scoreBg: Color(0xFFAF2025),
    btnTop: Color(0xFFC62F2F),
    btnBot: Color(0xFF94151E),
    linkLine: Color(0xFFE3A59D),
    tintZhu: Color(0xFFBF3A37),
    tintDai: Color(0xFF586A83),
    tintTan: Color(0xFF8F4C55),
    tintZhe: Color(0xFFA9733A),
    tintCi: Color(0xFF528581),
    tintMo: Color(0xFF615956),
  );

  /// 朱砂红 · 深色(1.0.8 定稿值)
  static const AppTokens cinnabarDark = AppTokens(
    style: AppearanceStyle.cinnabar,
    bg: Color(0xFF0D0B0A),
    grouped: Color(0xFF0D0B0A),
    surface: Color(0xFF1B1817),
    fill: Color.fromRGBO(130, 115, 110, .24),
    fill2: Color.fromRGBO(130, 115, 110, .36),
    fill3: Color.fromRGBO(130, 115, 110, .12),
    greenSoft: Color.fromRGBO(105, 192, 144, .09),
    greenFill: Radix.green3Dark,
    greenLine: Color.fromRGBO(105, 192, 144, .18),
    separator: Color.fromRGBO(110, 96, 92, .50),
    pressed: Color(0xFF231F1F),
    text: Color(0xFFEEEAE8),
    text2: Color(0xFFAFA7A5),
    text3: Color(0xFF726B6A),
    // 深色端红字提亮到 #EA857F,对比度优先
    accent: Color(0xFFEA857F),
    accentFill: Color(0xFF381C1A),
    accentFill2: Color(0xFF4A2321),
    accentLine: Color(0xFF843C39),
    // 深色主按钮白字
    onAccent: Color(0xFFFFFFFF),
    glass: Color.fromRGBO(46, 41, 40, .92),
    glassOnImage: Color.fromRGBO(30, 30, 32, .50),
    frostedMist: Color.fromRGBO(10, 8, 8, .30),
    red: Color(0xFFEA857F),
    green: Color(0xFF69C090),
    warn: Radix.amber11Dark,
    warnBg: Radix.amber3Dark,
    warnBorder: Color(0xFF4A3517),
    scrim: Color.fromRGBO(0, 0, 0, .56),
    // 深色漆面 #7A201E → #4A1311,文字对比度全面升高
    lacTop: Color(0xFF7A201E),
    lacMid: Color(0xFF5B1614),
    lacBot: Color(0xFF4A1311),
    onLac: Color(0xFFFFF8F5),
    onLac2: Color(0xFFF5CFC5),
    onLac3: Color.fromRGBO(255, 248, 245, .62),
    chipBg: Color(0xFF3E1613),
    chipText: Color(0xFFF0BCB2),
    unreadBg: Color(0xFF241110),
    scoreBg: Color(0xFFAC3130),
    btnTop: Color(0xFF9E2B2A),
    btnBot: Color(0xFF7E1A1F),
    linkLine: Color(0xFF843C39),
    tintZhu: Color(0xFFAF3D38),
    tintDai: Color(0xFF52657D),
    tintTan: Color(0xFF864851),
    tintZhe: Color(0xFF9B6833),
    tintCi: Color(0xFF4B7875),
    tintMo: Color(0xFF59504E),
  );

  /// 兼容别名(历史引用点与测试):不带 style 上下文时默认朱砂红
  static const AppTokens light = cinnabarLight;
  static const AppTokens dark = cinnabarDark;

  /// 薄雾白 · 浅色(1.0.7 基线 e112669 的原值)。
  ///
  /// 前半段是 1.0.7 的纸面色板;漆面相关令牌(lac*/onLac*/chip* 等)
  /// 给纸面退化值——薄雾白一级页不进 LacScaffold,这些值只在组件
  /// 意外走到漆面分支时兜底,保持中性不穿帮。
  /// 注:green3/amber3/amber11 的 Radix 步级在 v2 改过值,这里直接写
  /// 1.0.7 原值字面量。
  static const AppTokens mistyLight = AppTokens(
    style: AppearanceStyle.misty,
    bg: Color(0xFFFFFFFF),
    grouped: Color(0xFFF2F2F7),
    surface: Color(0xFFFFFFFF),
    fill: Color.fromRGBO(118, 118, 128, .12),
    fill2: Color.fromRGBO(118, 118, 128, .22),
    fill3: Color.fromRGBO(118, 118, 128, .06),
    greenSoft: Color.fromRGBO(43, 154, 102, .09),
    greenFill: Color(0xFFE6F6EB), // 1.0.7 Radix.green3Light
    greenLine: Color.fromRGBO(33, 131, 88, .16),
    separator: Color.fromRGBO(60, 60, 67, .16),
    pressed: Color(0xFFE5E5EA),
    text: Color(0xFF1C2024),
    text2: Color(0xFF6B6E76),
    text3: Color(0xFFA0A3AB),
    accent: Color(0xFF0D74CE),
    accentFill: Color.fromRGBO(13, 116, 206, .12),
    accentFill2: Color.fromRGBO(13, 116, 206, .12),
    accentLine: Color(0xFFD9D9E0),
    onAccent: Color(0xFFFFFFFF),
    glass: Color.fromRGBO(255, 255, 255, .92),
    glassOnImage: Color.fromRGBO(30, 30, 32, .50),
    frostedMist: Color.fromRGBO(255, 255, 255, .38),
    red: Color(0xFFE5484D),
    green: Color(0xFF2B9A66),
    warn: Color(0xFFAB6400), // 1.0.7 Radix.amber11Light
    warnBg: Color(0xFFFFF7C2), // 1.0.7 Radix.amber3Light
    warnBorder: Color(0xFFF3D673),
    scrim: Color(0x6B1C2024),
    // 漆面组退化:渐变退成纸面纯色,漆面文字退成纸面文字
    lacTop: Color(0xFFFFFFFF),
    lacMid: Color(0xFFFFFFFF),
    lacBot: Color(0xFFFFFFFF),
    onLac: Color(0xFF1C2024),
    onLac2: Color(0xFF6B6E76),
    onLac3: Color(0xFFA0A3AB),
    chipBg: Color.fromRGBO(118, 118, 128, .12),
    chipText: Color(0xFF6B6E76),
    unreadBg: Color(0xFFFFFFFF),
    scoreBg: Color.fromRGBO(13, 116, 206, .12),
    btnTop: Color(0xFF0D74CE),
    btnBot: Color(0xFF0D74CE),
    linkLine: Color(0x590D74CE),
    // 入口图标色:1.0.7 的 IconTints 色板(国色线形组是 v2 引入)
    tintZhu: Color(0xFF0090FF),
    tintDai: Color(0xFF8E4EC6),
    tintTan: Color(0xFFF76B15),
    tintZhe: Color(0xFF12A594),
    tintCi: Color(0xFF30A46C),
    tintMo: Color(0xFF8B8D98),
  );

  /// 薄雾白 · 深色(1.0.7 基线的深色组 + 同规则退化值)
  static const AppTokens mistyDark = AppTokens(
    style: AppearanceStyle.misty,
    bg: Color(0xFF0B0B0C),
    grouped: Color(0xFF0B0B0C),
    surface: Color(0xFF1C1C1E),
    fill: Color.fromRGBO(118, 118, 128, .24),
    fill2: Color.fromRGBO(118, 118, 128, .36),
    fill3: Color.fromRGBO(118, 118, 128, .12),
    greenSoft: Color.fromRGBO(61, 214, 140, .09),
    greenFill: Color(0xFF132D21), // 1.0.7 Radix.green3Dark
    greenLine: Color.fromRGBO(61, 214, 140, .18),
    separator: Color.fromRGBO(84, 84, 88, .60),
    pressed: Color(0xFF2C2C2F),
    text: Color(0xFFEDEEF0),
    text2: Color(0xFFA1A4AB),
    text3: Color(0xFF6E7179),
    accent: Color(0xFF70B8FF),
    accentFill: Color.fromRGBO(112, 184, 255, .16),
    accentFill2: Color.fromRGBO(112, 184, 255, .16),
    accentLine: Color(0xFF363A3F),
    onAccent: Color(0xFF0B0B0C),
    glass: Color.fromRGBO(44, 44, 48, .92),
    glassOnImage: Color.fromRGBO(30, 30, 32, .50),
    frostedMist: Color.fromRGBO(16, 16, 18, .30),
    red: Color(0xFFFF6369),
    green: Color(0xFF3DD68C),
    warn: Color(0xFFFFCA16), // 1.0.7 Radix.amber11Dark
    warnBg: Color(0xFF302008), // 1.0.7 Radix.amber3Dark
    warnBorder: Color(0xFF5C3D05),
    scrim: Color(0x941C2024),
    lacTop: Color(0xFF0B0B0C),
    lacMid: Color(0xFF0B0B0C),
    lacBot: Color(0xFF0B0B0C),
    onLac: Color(0xFFEDEEF0),
    onLac2: Color(0xFFA1A4AB),
    onLac3: Color(0xFF6E7179),
    chipBg: Color.fromRGBO(118, 118, 128, .24),
    chipText: Color(0xFFA1A4AB),
    unreadBg: Color(0xFF0B0B0C),
    scoreBg: Color.fromRGBO(112, 184, 255, .16),
    btnTop: Color(0xFF70B8FF),
    btnBot: Color(0xFF70B8FF),
    linkLine: Color(0x5970B8FF),
    tintZhu: Color(0xFF0090FF),
    tintDai: Color(0xFF8E4EC6),
    tintTan: Color(0xFFF76B15),
    tintZhe: Color(0xFF12A594),
    tintCi: Color(0xFF30A46C),
    tintMo: Color(0xFF8B8D98),
  );

  static AppTokens of(BuildContext context) =>
      Theme.of(context).extension<AppTokens>() ?? light;

  /// 页面底色:内容页用 bg,分组页用 grouped
  Color background(AppSurface s) => switch (s) {
    AppSurface.content => bg,
    AppSurface.grouped => grouped,
  };

  bool get isDark => bg.computeLuminance() < 0.3;

  /// Thread section bands are slightly lighter than the dark page background.
  Color get threadSectionBand => isDark
      ? (style == AppearanceStyle.misty
            ? const Color(0xFF151517)
            : const Color(0xFF1A1514))
      : grouped;

  /// 一级页漆面渐变(顶栏、启动页)。168° 在竖屏下近似竖向。
  LinearGradient get lacGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [lacTop, lacMid, lacBot],
    stops: const [0, .55, 1],
  );

  /// 实心红按钮的漆面渐变
  LinearGradient get btnGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [btnTop, btnBot],
  );

  /// 纸面接缝投影:红调深影,让纸"浮"在漆面上
  List<BoxShadow> get paperShadow => [
    BoxShadow(
      color: isDark ? const Color(0x80000000) : const Color(0x61460A0E),
      offset: const Offset(0, -10),
      blurRadius: 30,
      spreadRadius: -14,
    ),
  ];

  /// 漆面实心按钮投影(红调;Flutter 无内阴影,高光由渐变自身表现)。
  /// 薄雾白主按钮是纯色 accent,配中性轻影,不带红光晕。
  List<BoxShadow> get btnShadow => style == AppearanceStyle.misty
      ? const [
          BoxShadow(
            color: Color(0x1A000000),
            offset: Offset(0, 2),
            blurRadius: 8,
          ),
        ]
      : isDark
      ? const [
          BoxShadow(
            color: Color(0x80000000),
            offset: Offset(0, 1),
            blurRadius: 2,
          ),
          BoxShadow(
            color: Color(0x80C82D2D),
            offset: Offset(0, 8),
            blurRadius: 20,
            spreadRadius: -10,
          ),
        ]
      : const [
          BoxShadow(
            color: Color(0x2E780F0F),
            offset: Offset(0, 1),
            blurRadius: 2,
          ),
          BoxShadow(
            color: Color(0x80961419),
            offset: Offset(0, 8),
            blurRadius: 18,
            spreadRadius: -8,
          ),
        ];

  // ---- 层级阴影 ----
  //
  // 0.5px 描边用 spreadRadius .5 / blurRadius 0 的阴影实现,
  // 这样描边和投影在同一个 boxShadow 里,圆角形状无需额外 border。

  /// e1:浮动圆钮、胶囊、分段滑块、阅读工具栏。
  /// 朱砂红用暖调影,薄雾白用 1.0.7 的中性影。
  List<BoxShadow> get shadowE1 => style == AppearanceStyle.misty
      ? [
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
        ]
      : [
          BoxShadow(
            color: isDark ? const Color(0x17FFF0EB) : const Color(0x143C1E19),
            spreadRadius: .5,
            blurRadius: 0,
          ),
          BoxShadow(
            color: isDark ? const Color(0x80000000) : const Color(0x143C1E19),
            offset: const Offset(0, 2),
            blurRadius: 8,
          ),
        ];

  /// e2:精选大卡、横滑卡
  List<BoxShadow> get shadowE2 => style == AppearanceStyle.misty
      ? (isDark
            ? const [
                BoxShadow(
                  color: Color(0x14FFFFFF),
                  spreadRadius: .5,
                  blurRadius: 0,
                ),
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
              ])
      : isDark
      ? const [
          BoxShadow(color: Color(0x12FFF0EB), spreadRadius: .5, blurRadius: 0),
          BoxShadow(
            color: Color(0x99000000),
            offset: Offset(0, 10),
            blurRadius: 28,
          ),
        ]
      : const [
          BoxShadow(
            color: Color(0x0F321914),
            offset: Offset(0, 1),
            blurRadius: 3,
          ),
          BoxShadow(
            color: Color(0x1A321914),
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
    Color? fill3,
    Color? greenSoft,
    Color? greenFill,
    Color? greenLine,
    Color? separator,
    Color? pressed,
    Color? text,
    Color? text2,
    Color? text3,
    Color? accent,
    Color? accentFill,
    Color? accentFill2,
    Color? accentLine,
    Color? onAccent,
    Color? glass,
    Color? glassOnImage,
    Color? frostedMist,
    Color? red,
    Color? green,
    Color? warn,
    Color? warnBg,
    Color? warnBorder,
    Color? scrim,
    Color? lacTop,
    Color? lacMid,
    Color? lacBot,
    Color? onLac,
    Color? onLac2,
    Color? onLac3,
    Color? chipBg,
    Color? chipText,
    Color? unreadBg,
    Color? scoreBg,
    Color? btnTop,
    Color? btnBot,
    Color? linkLine,
    Color? tintZhu,
    Color? tintDai,
    Color? tintTan,
    Color? tintZhe,
    Color? tintCi,
    Color? tintMo,
  }) {
    return AppTokens(
      style: style,
      bg: bg ?? this.bg,
      grouped: grouped ?? this.grouped,
      surface: surface ?? this.surface,
      fill: fill ?? this.fill,
      fill2: fill2 ?? this.fill2,
      fill3: fill3 ?? this.fill3,
      greenSoft: greenSoft ?? this.greenSoft,
      greenFill: greenFill ?? this.greenFill,
      greenLine: greenLine ?? this.greenLine,
      separator: separator ?? this.separator,
      pressed: pressed ?? this.pressed,
      text: text ?? this.text,
      text2: text2 ?? this.text2,
      text3: text3 ?? this.text3,
      accent: accent ?? this.accent,
      accentFill: accentFill ?? this.accentFill,
      accentFill2: accentFill2 ?? this.accentFill2,
      accentLine: accentLine ?? this.accentLine,
      onAccent: onAccent ?? this.onAccent,
      glass: glass ?? this.glass,
      glassOnImage: glassOnImage ?? this.glassOnImage,
      frostedMist: frostedMist ?? this.frostedMist,
      red: red ?? this.red,
      green: green ?? this.green,
      warn: warn ?? this.warn,
      warnBg: warnBg ?? this.warnBg,
      warnBorder: warnBorder ?? this.warnBorder,
      scrim: scrim ?? this.scrim,
      lacTop: lacTop ?? this.lacTop,
      lacMid: lacMid ?? this.lacMid,
      lacBot: lacBot ?? this.lacBot,
      onLac: onLac ?? this.onLac,
      onLac2: onLac2 ?? this.onLac2,
      onLac3: onLac3 ?? this.onLac3,
      chipBg: chipBg ?? this.chipBg,
      chipText: chipText ?? this.chipText,
      unreadBg: unreadBg ?? this.unreadBg,
      scoreBg: scoreBg ?? this.scoreBg,
      btnTop: btnTop ?? this.btnTop,
      btnBot: btnBot ?? this.btnBot,
      linkLine: linkLine ?? this.linkLine,
      tintZhu: tintZhu ?? this.tintZhu,
      tintDai: tintDai ?? this.tintDai,
      tintTan: tintTan ?? this.tintTan,
      tintZhe: tintZhe ?? this.tintZhe,
      tintCi: tintCi ?? this.tintCi,
      tintMo: tintMo ?? this.tintMo,
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

/// 圆角令牌。rFull 用 StadiumBorder / CircleBorder,不在此定义。
abstract final class AppRadii {
  static const double full = 999;

  /// 拖动条、细进度条这类 4–5dp 高的胶囊
  static const double bar = 2.5;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 18;
  static const double lg = 24;
  static const double xl = 28;

  /// 纸面接缝的顶圆角(漆面一级页)
  static const double paper = 26;
}

/// 间距令牌
abstract final class AppSpace {
  static const double screen = 20;
  static const double groupInset = 16;
  static const double rowInset = 16;
  static const double section = 28;
  static const double hairline = 0.5;

  /// 纸面上浮盖住漆面的深度(接缝)
  static const double seam = 26;

  /// 漆面 mast 区统一高度(分段/身份卡等顶对齐其内):
  /// 四个一级页的纸面岛起点一致,切换页签时不跳动。
  /// 66 = 我的身份卡收紧后自然高(8+54+4)。
  static const double mastRegion = 66;

  /// 大标题行统一高度:accessory 圆钮/胶囊不撑高头部,四页一致
  static const double titleRow = 44;
}

/// 设置类行 30dp 图标底的国色色板:名字保留旧语义,值换成国色组
abstract final class IconTints {
  static const blue = Color(0xFF586A83); // 黛
  static const orange = Color(0xFFA9733A); // 赭
  static const green = Color(0xFF528581); // 瓷
  static const violet = Color(0xFF8F4C55); // 檀
  static const teal = Color(0xFF528581); // 瓷(工具行)
  static const gray = Color(0xFF615956); // 墨(工具行)
}

/// 漆面品牌元素的固定展示尺寸与叠层色(水印、启动屏;设计稿 v2)
abstract final class LacquerMarks {
  /// 一级页右上角的 chh 水印字号
  static const double watermark = 104;

  /// 启动屏的 chh 标与字标字号
  static const double launchMark = 64;
  static const double launchWord = 30;

  /// 启动屏底部的径向光晕与白标投影
  static const Color launchGlow = Color(0xFF79131A);
  static const Color launchMarkShadow = Color(0x4D3C0000);
}

/// 压在照片上的颜色:与主题无关,照片上永远是深色遮罩配浅色字
abstract final class ImageColors {
  static const foreground = Color(0xFFFCFCFD);
  static const shade = Color(0xFF1C2024);
  static const viewerBackground = Color(0xFF111113);
  static const viewerForeground = Color(0xFFEDEEF0);
}

/// Fixed metadata sizes from the thread detail design; reading text uses ReadingMetrics.
abstract final class ThreadMetrics {
  static const metaSize = 12.5;
  static const headingSize = 20.0;
  static const pillRadius = 15.0;
  static const forumRadius = 13.0;
}
