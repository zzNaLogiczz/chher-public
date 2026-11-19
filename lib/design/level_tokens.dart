import 'package:flutter/material.dart';

import 'tokens.dart';

enum LevelAnimation { none, shimmer, shimmerSparkle, slowShimmer }

/// Authoritative whitelist from the confirmed 2026-11-16 level design.
@immutable
class LevelDefinition {
  const LevelDefinition(
    this.gid,
    this.displayName,
    this.glyph,
    this.tier,
    this.longPress, {
    this.threshold,
    this.darkTile = false,
    this.animation = LevelAnimation.none,
  });
  final int gid;
  final String displayName, glyph, tier, longPress;
  final int? threshold;
  final bool darkTile;
  final LevelAnimation animation;
  bool get animated => animation != LevelAnimation.none;
  bool get sparkle => animation == LevelAnimation.shimmerSparkle;
  static LevelDefinition? lookup(int? gid) => all[gid];
  static const all = <int, LevelDefinition>{
    59: LevelDefinition(59, '亡灵', 'ghost', 'ash', '积分为负'),
    49: LevelDefinition(
      49,
      '实习天使',
      'feather',
      'silver',
      '积分 0 起',
      threshold: 0,
    ),
    38: LevelDefinition(38, '天使', 'halo', 'silver', '积分 5 起', threshold: 5),
    39: LevelDefinition(39, '大天使', 'wings', 'jade', '积分 500 起', threshold: 500),
    40: LevelDefinition(
      40,
      '权天使',
      'scepter',
      'jade',
      '积分 1,500 起',
      threshold: 1500,
    ),
    41: LevelDefinition(
      41,
      '能天使',
      'shield',
      'sapph',
      '积分 2,500 起',
      threshold: 2500,
    ),
    42: LevelDefinition(
      42,
      '力天使',
      'bolt',
      'sapph',
      '积分 4,000 起',
      threshold: 4000,
    ),
    43: LevelDefinition(
      43,
      '主天使',
      'crown',
      'iris',
      '积分 6,000 起',
      threshold: 6000,
    ),
    44: LevelDefinition(
      44,
      '座天使',
      'throne',
      'iris',
      '积分 8,500 起',
      threshold: 8500,
    ),
    45: LevelDefinition(
      45,
      '智天使',
      'eye',
      'amber',
      '积分 11,000 起',
      threshold: 11000,
    ),
    46: LevelDefinition(
      46,
      '炽天使',
      'flame',
      'ember',
      '积分 15,000 起',
      threshold: 15000,
    ),
    48: LevelDefinition(
      48,
      '小恶魔',
      'imp',
      'ruby',
      '积分 20,000 起',
      threshold: 20000,
    ),
    1: LevelDefinition(
      1,
      '圣魔王',
      'demoncrown',
      'gold',
      '圣魔王- "傻蛋"',
      darkTile: true,
      animation: LevelAnimation.shimmerSparkle,
    ),
    2: LevelDefinition(
      2,
      '圣魔灵',
      'morningstar',
      'gold',
      '圣魔灵-路西法',
      darkTile: true,
      animation: LevelAnimation.shimmer,
    ),
    3: LevelDefinition(
      3,
      '圣魔使',
      'trident',
      'gold',
      '圣魔使-迪亚波罗',
      darkTile: true,
      animation: LevelAnimation.shimmer,
    ),
    56: LevelDefinition(
      56,
      '见习迪亚波罗',
      'trident',
      'champ',
      '见习-迪亚波罗',
      darkTile: true,
      animation: LevelAnimation.slowShimmer,
    ),
    55: LevelDefinition(
      55,
      '大恶魔',
      'archfiend',
      'fiend',
      '大恶魔',
      darkTile: true,
      animation: LevelAnimation.none,
    ),
    64: LevelDefinition(
      64,
      '大恶魔',
      'archfiend',
      'fiendG',
      '大恶魔(绿)',
      darkTile: true,
      animation: LevelAnimation.none,
    ),
  };
}

@immutable
class LevelPalette {
  const LevelPalette({
    required this.a,
    required this.b,
    required this.i,
    required this.j,
    this.glow,
    this.tile,
    this.tgD,
    this.tgL,
  });
  final Color a, b, i, j;
  final Color? glow;
  final List<Color>? tile, tgD, tgL;
  static LevelPalette forStyle(AppearanceStyle style, String tier) =>
      (style == AppearanceStyle.misty ? misty : cinnabar)[tier]!;
  static const misty = <String, LevelPalette>{
    'ash': LevelPalette(
      a: Color(0xFFC9CDD4),
      b: Color(0xFF7C828D),
      i: Color(0xFF6B6E76),
      j: Color(0xFF9CA0A8),
    ),
    'silver': LevelPalette(
      a: Color(0xFFDCE2EB),
      b: Color(0xFF8794A8),
      i: Color(0xFF5D6675),
      j: Color(0xFFB9C1CD),
    ),
    'jade': LevelPalette(
      a: Color(0xFF8BE0B9),
      b: Color(0xFF1E8A5E),
      i: Color(0xFF1B7A4F),
      j: Color(0xFF6FD9A3),
    ),
    'sapph': LevelPalette(
      a: Color(0xFF97C6FF),
      b: Color(0xFF2D68D6),
      i: Color(0xFF1F5DB5),
      j: Color(0xFF8DBEFF),
    ),
    'iris': LevelPalette(
      a: Color(0xFFC9B0FF),
      b: Color(0xFF6E46D6),
      i: Color(0xFF6A3DB0),
      j: Color(0xFFC9A2F5),
    ),
    'amber': LevelPalette(
      a: Color(0xFFFFD989),
      b: Color(0xFFE0841C),
      i: Color(0xFFA6580A),
      j: Color(0xFFF2B064),
    ),
    'ember': LevelPalette(
      a: Color(0xFFFFBE8C),
      b: Color(0xFFE04B26),
      i: Color(0xFFB7420F),
      j: Color(0xFFFF9A5C),
    ),
    'ruby': LevelPalette(
      a: Color(0xFFFF9AA3),
      b: Color(0xFFD0263D),
      i: Color(0xFFC42839),
      j: Color(0xFFFF8F95),
      glow: Color.fromRGBO(226, 48, 64, 0.45),
    ),
    'fiend': LevelPalette(
      a: Color(0xFFFF9C9C),
      b: Color(0xFFFF2E46),
      tile: [Color(0xFF3E141B), Color(0xFF0F0507)],
      i: Color(0xFFE33246),
      j: Color(0xFFFF7C86),
      glow: Color.fromRGBO(232, 40, 56, 0.6),
      tgD: [Color(0xFFFFE0DA), Color(0xFFFF6E62)],
      tgL: [Color(0xFFEC4A56), Color(0xFFA3101F)],
    ),
    'fiendG': LevelPalette(
      a: Color(0xFF9CFFC8),
      b: Color(0xFF22D07A),
      tile: [Color(0xFF10402A), Color(0xFF041109)],
      i: Color(0xFF178A50),
      j: Color(0xFF5DE29A),
      glow: Color.fromRGBO(34, 200, 110, 0.55),
      tgD: [Color(0xFFE2FCEB), Color(0xFF4FDB8F)],
      tgL: [Color(0xFF2BB06C), Color(0xFF0E6A3C)],
    ),
    'gold': LevelPalette(
      a: Color(0xFFFFF0B8),
      b: Color(0xFFE2A63A),
      tile: [Color(0xFF3A2E19), Color(0xFF0E0B07)],
      i: Color(0xFFA87516),
      j: Color(0xFFF4C860),
      glow: Color.fromRGBO(236, 182, 72, 0.62),
      tgD: [Color(0xFFFFF4CC), Color(0xFFF2C35A), Color(0xFFC1861F)],
      tgL: [Color(0xFFE0AE45), Color(0xFFB07A1A), Color(0xFF7E540C)],
    ),
    'champ': LevelPalette(
      a: Color(0xFFFFFFFF),
      b: Color(0xFFCDB88A),
      tile: [Color(0xFF33302B), Color(0xFF0F0E0C)],
      i: Color(0xFF8C7A55),
      j: Color(0xFFE2CC9A),
      glow: Color.fromRGBO(214, 190, 140, 0.42),
      tgD: [Color(0xFFFFFFFF), Color(0xFFD6C29A)],
      tgL: [Color(0xFFBBA77D), Color(0xFF7A6844)],
    ),
  };
  static const cinnabar = <String, LevelPalette>{
    'ash': LevelPalette(
      a: Color(0xFFCFC7C4),
      b: Color(0xFF857A77),
      i: Color(0xFF7A706E),
      j: Color(0xFF978C89),
    ),
    'silver': LevelPalette(
      a: Color(0xFFE2DCDA),
      b: Color(0xFF948A87),
      i: Color(0xFF625A58),
      j: Color(0xFFC4BAB7),
    ),
    'jade': LevelPalette(
      a: Color(0xFF9ACDBD),
      b: Color(0xFF2F6E5E),
      i: Color(0xFF2D6A5B),
      j: Color(0xFFA0D1C1),
    ),
    'sapph': LevelPalette(
      a: Color(0xFFA9BCD6),
      b: Color(0xFF3E5A7E),
      i: Color(0xFF3B5574),
      j: Color(0xFFB3C5DD),
    ),
    'iris': LevelPalette(
      a: Color(0xFFC7AED6),
      b: Color(0xFF6A3F82),
      i: Color(0xFF683B7E),
      j: Color(0xFFC9ACD8),
    ),
    'amber': LevelPalette(
      a: Color(0xFFF0CC8E),
      b: Color(0xFFB06A1E),
      i: Color(0xFF9A5B22),
      j: Color(0xFFE4AD6C),
    ),
    'ember': LevelPalette(
      a: Color(0xFFF2AE8A),
      b: Color(0xFFB2401C),
      i: Color(0xFFA8461A),
      j: Color(0xFFEE9A6A),
    ),
    'ruby': LevelPalette(
      a: Color(0xFFF29A94),
      b: Color(0xFFA51D24),
      i: Color(0xFFAF2025),
      j: Color(0xFFEE8D87),
      glow: Color.fromRGBO(175, 32, 37, 0.42),
    ),
    'fiend': LevelPalette(
      a: Color(0xFFFF9C9C),
      b: Color(0xFFF0303E),
      tile: [Color(0xFF3A1216), Color(0xFF0E0506)],
      i: Color(0xFFB8242C),
      j: Color(0xFFFF7C86),
      glow: Color.fromRGBO(200, 36, 44, 0.58),
      tgD: [Color(0xFFFFE0DA), Color(0xFFFF6E62)],
      tgL: [Color(0xFFEC4A56), Color(0xFFA3101F)],
    ),
    'fiendG': LevelPalette(
      a: Color(0xFF9CFFC8),
      b: Color(0xFF22C06E),
      tile: [Color(0xFF10402A), Color(0xFF041109)],
      i: Color(0xFF1F6E48),
      j: Color(0xFF5DE29A),
      glow: Color.fromRGBO(34, 190, 100, 0.5),
      tgD: [Color(0xFFE2FCEB), Color(0xFF4FDB8F)],
      tgL: [Color(0xFF2BB06C), Color(0xFF0E6A3C)],
    ),
    'gold': LevelPalette(
      a: Color(0xFFFFF0B8),
      b: Color(0xFFDDA238),
      tile: [Color(0xFF382B17), Color(0xFF0D0A06)],
      i: Color(0xFF9A6A12),
      j: Color(0xFFF4C860),
      glow: Color.fromRGBO(230, 176, 70, 0.6),
      tgD: [Color(0xFFFFF4CC), Color(0xFFF2C35A), Color(0xFFC1861F)],
      tgL: [Color(0xFFE0AE45), Color(0xFFB07A1A), Color(0xFF7E540C)],
    ),
    'champ': LevelPalette(
      a: Color(0xFFFFFFFF),
      b: Color(0xFFCDB88A),
      tile: [Color(0xFF33302B), Color(0xFF0F0E0C)],
      i: Color(0xFF857350),
      j: Color(0xFFE2CC9A),
      glow: Color.fromRGBO(214, 190, 140, 0.4),
      tgD: [Color(0xFFFFFFFF), Color(0xFFD6C29A)],
      tgL: [Color(0xFFBBA77D), Color(0xFF7A6844)],
    ),
  };
}

abstract final class LevelTokens {
  static const height = 20.0;
  static const radius = 6.0;
  static const tileSize = 16.0;
  static const tileRadius = 4.0;
  static const fontSize = 12.0;
  static const fontWeight = FontWeight.w600;
  static const iconSize = 12.0;
  static const gap = 4.0;
  static const authorGap = 6.0;
  static const authorNameMinWidth = 24.0;
  static const ownerHeight = 18.0;
  static const ownerRadius = 5.0;
  static const ownerInset = 5.0;
  static const ownerBorder = 1.0;
  static const ownerBorderAlpha = .5;
  static const ownerFontSize = 11.0;
  static const ownerText = '楼主';
  static const ownerStyle = TextStyle(
    fontSize: ownerFontSize,
    fontWeight: fontWeight,
    height: 1,
  );
  static const coldTiers = {'jade', 'sapph', 'iris'};
  static const inset = 2.0;
  static const rightInset = 7.0;
  static const glyphGrid = 24.0;
  static const glyphStroke = 1.7;
  static const glyphFillAlpha = .30;
  static const lightPlateAlpha = .22;
  static const darkPlateAlpha = .26;
  static const glazeAlpha = .42;
  static const royalGlazeAlpha = .14;
  static const glazeStop = .58;
  static const royalGlazeStop = .55;
  static const shimmerBandHalfWidth = .10;
  static const shimmerTravel = 1.4;
  static const shimmerStart = -.2;
  static const letterSpacing = .6;
  static const sparkleSize = 8.0;
  static const sparkleLeft = 12.0;
  static const sparkleTop = -4.0;
  static const sweep = Duration(milliseconds: 1300);
  static const slowSweep = Duration(milliseconds: 1600);
  static const pause = Duration(milliseconds: 1700);
  static const slowPause = Duration(milliseconds: 4800);
  static const sparkle = Duration(milliseconds: 700);
  static const sparkleDelay = Duration(milliseconds: 1400);
  static const burst = Duration(milliseconds: 2900);
  static const cycleSeconds = 4.6;
  static const particleLife = cycleSeconds * particleGoneAt;
  static const particleCurve = Cubic(.2, .6, .3, 1);
  static const particleGlowRadius = 3.0;
  static const particleEndScale = .4;
  static const flareCenter = Offset(.30, 1.20);
  static const flareRadii = Offset(1.20, 2);
  static const flareStop = .65;
  static const particleBrightAt = .04;
  static const particleDimAt = .26;
  static const particleGoneAt = .44;
  static const particleDimAlpha = .85;
  static const flarePeak = .37;
  static const flareEnd = 1.84;
  static const shimmerAlpha = .95;
  static const sparkCore = Color(0xFFFFFBEA);
  static const sparkGold = Color(0xFFFFD978);
  static const sparkEdge = Color.fromRGBO(255, 184, 64, 0);
  static const sparkGlow = Color.fromRGBO(255, 200, 96, .85);
  static const flareColor = Color.fromRGBO(255, 190, 80, .38);
  static const white = Color(0xFFFFFFFF);
  static const highlight = Color(0xFFFFFDF2);
  static const sunken = Color.fromRGBO(0, 0, 0, .45);
  static const sunkenOffset = Offset(0, 1);
  static const sunkenBlur = 2.0;
  static const sunkenSpread = -1.0;

  static List<BoxShadow> shadows(
    LevelPalette palette, {
    required String tier,
    required bool royal,
    double scale = 1,
  }) => [
    if (royal)
      BoxShadow(
        color: sunken,
        offset: sunkenOffset * scale,
        blurRadius: sunkenBlur * scale,
        spreadRadius: sunkenSpread * scale,
      ),
  ];

  static LevelGlowSpec? innerGlow(String tier, bool dark, double scale) =>
      switch (tier) {
        'ruby' => LevelGlowSpec(
          Offset(9 * scale, height * scale * .5),
          const Offset(.70, 1.60),
          .72,
          dark
              ? const Color.fromRGBO(255, 90, 105, .30)
              : const Color.fromRGBO(255, 120, 130, .34),
        ),
        'fiend' => LevelGlowSpec(
          Offset(0, height * scale),
          const Offset(.90, 1.90),
          .70,
          const Color.fromRGBO(255, 50, 70, .42),
        ),
        'fiendG' => LevelGlowSpec(
          Offset(0, height * scale),
          const Offset(.90, 1.90),
          .70,
          const Color.fromRGBO(40, 230, 130, .32),
        ),
        'gold' || 'champ' => LevelGlowSpec(
          Offset(9 * scale, height * scale * .55),
          const Offset(.85, 1.70),
          .72,
          tier == 'gold'
              ? const Color.fromRGBO(255, 196, 84, .34)
              : const Color.fromRGBO(240, 226, 196, .16),
        ),
        _ => null,
      };

  static const sparks = <LevelSparkSpec>[
    LevelSparkSpec(.08, 15, 2.4, 10, -15, 0),
    LevelSparkSpec(.22, 16, 1.8, 6, -13, .10),
    LevelSparkSpec(.36, 15, 2.2, -4, -16, .22),
    LevelSparkSpec(.50, 16, 1.6, 8, -12, .05),
    LevelSparkSpec(.64, 15, 2.6, -6, -17, .32),
    LevelSparkSpec(.78, 16, 1.7, 4, -13, .16),
    LevelSparkSpec(.14, 17, 1.5, 14, -11, .50),
    LevelSparkSpec(.44, 17, 2.0, 10, -15, .62),
    LevelSparkSpec(.70, 17, 1.5, -8, -12, .44),
    LevelSparkSpec(.28, 16, 2.2, -5, -17, .74),
    LevelSparkSpec(.58, 16, 1.4, 12, -14, .86),
    LevelSparkSpec(.86, 16, 2.0, -6, -15, .58),
  ];

  // CSS 155deg runs from upper left to lower right.
  static LinearGradient diagonal(List<Color> colors) => LinearGradient(
    begin: const Alignment(-.422618, -.906308),
    end: const Alignment(.422618, .906308),
    colors: colors,
  );
  static List<Color> tileColors(String tier) => switch (tier) {
    'gold' => const [Color(0xFF4C3B1D), Color(0xFF1C150B)],
    'champ' => const [Color(0xFF45403A), Color(0xFF1A1816)],
    'fiend' => const [Color(0xFF4E1820), Color(0xFF1A0709)],
    'fiendG' => const [Color(0xFF154A30), Color(0xFF06160D)],
    _ => throw ArgumentError.value(tier, 'tier'),
  };
}

@immutable
class LevelGlowSpec {
  const LevelGlowSpec(this.center, this.radii, this.stop, this.color);
  final Offset center, radii;
  final double stop;
  final Color color;
}

@immutable
class LevelSparkSpec {
  const LevelSparkSpec(this.x, this.y, this.size, this.dx, this.dy, this.delay);
  final double x, y, size, dx, dy, delay;
}
