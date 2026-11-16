import 'package:chh_app/design/level_tokens.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'only the 18 confirmed gids have the specified name, glyph and tier',
    () {
      const expected = {
        59: ('亡灵', 'ghost', 'ash'),
        49: ('实习天使', 'feather', 'silver'),
        38: ('天使', 'halo', 'silver'),
        39: ('大天使', 'wings', 'jade'),
        40: ('权天使', 'scepter', 'jade'),
        41: ('能天使', 'shield', 'sapph'),
        42: ('力天使', 'bolt', 'sapph'),
        43: ('主天使', 'crown', 'iris'),
        44: ('座天使', 'throne', 'iris'),
        45: ('智天使', 'eye', 'amber'),
        46: ('炽天使', 'flame', 'ember'),
        48: ('小恶魔', 'imp', 'ruby'),
        1: ('圣魔王', 'demoncrown', 'gold'),
        2: ('圣魔灵', 'morningstar', 'gold'),
        3: ('圣魔使', 'trident', 'gold'),
        56: ('见习迪亚波罗', 'trident', 'champ'),
        55: ('大恶魔', 'archfiend', 'fiend'),
        64: ('大恶魔', 'archfiend', 'fiendG'),
      };
      expect(LevelDefinition.all.keys, unorderedEquals(expected.keys));
      for (final entry in expected.entries) {
        final level = LevelDefinition.lookup(entry.key)!;
        expect(level.gid, entry.key);
        expect((level.displayName, level.glyph, level.tier), entry.value);
        expect(level.darkTile, [1, 2, 3, 56, 55, 64].contains(entry.key));
        expect(level.animated, [1, 2, 3, 56].contains(entry.key));
        expect(level.sparkle, entry.key == 1);
      }
      for (final gid in [null, 4, 54, 63, 65, 7, -1, 999]) {
        expect(LevelDefinition.lookup(gid), isNull);
      }
    },
  );

  test(
    'thresholds and management descriptions preserve confirmed source text',
    () {
      const thresholds = {
        49: 0,
        38: 5,
        39: 500,
        40: 1500,
        41: 2500,
        42: 4000,
        43: 6000,
        44: 8500,
        45: 11000,
        46: 15000,
        48: 20000,
      };
      for (final entry in thresholds.entries) {
        final level = LevelDefinition.lookup(entry.key)!;
        expect(level.threshold, entry.value);
        expect(level.longPress, startsWith('积分 '));
        expect(level.longPress, endsWith(' 起'));
        expect(level.longPress, isNot(contains('上限')));
      }
      expect(LevelDefinition.lookup(41)!.longPress, '积分 2,500 起');
      const special = {
        59: '积分为负',
        1: '圣魔王- "傻蛋"',
        2: '圣魔灵-路西法',
        3: '圣魔使-迪亚波罗',
        56: '见习-迪亚波罗',
        55: '大恶魔',
        64: '大恶魔(绿)',
      };
      for (final entry in special.entries) {
        final level = LevelDefinition.lookup(entry.key)!;
        expect(level.threshold, isNull);
        expect(level.longPress, entry.value);
      }
      expect(LevelDefinition.lookup(56)!.animation, LevelAnimation.slowShimmer);
    },
  );

  test('inner light uses confirmed geometry and separate ruby modes', () {
    for (final dark in [false, true]) {
      final ruby = LevelTokens.innerGlow('ruby', dark, 1)!;
      expect(ruby.center, const Offset(9, 10));
      expect(ruby.radii, const Offset(.7, 1.6));
      expect(ruby.stop, .72);
      expect(
        ruby.color,
        dark
            ? const Color.fromRGBO(255, 90, 105, .30)
            : const Color.fromRGBO(255, 120, 130, .34),
      );
      for (final tier in ['fiend', 'fiendG']) {
        final glow = LevelTokens.innerGlow(tier, dark, 1)!;
        expect(glow.center, const Offset(0, 20));
        expect(glow.radii, const Offset(.9, 1.9));
        expect(glow.stop, .7);
      }
      for (final tier in ['gold', 'champ']) {
        final glow = LevelTokens.innerGlow(tier, dark, 2)!;
        expect(glow.center, const Offset(18, 22));
        expect(glow.radii, const Offset(.85, 1.7));
        expect(glow.stop, .72);
      }
      expect(LevelTokens.innerGlow('sapph', dark, 1), isNull);
    }
  });

  test('both palettes cover every tier including royal gradients', () {
    for (final style in AppearanceStyle.values) {
      for (final level in LevelDefinition.all.values) {
        final palette = LevelPalette.forStyle(style, level.tier);
        expect(palette.a.a, 1);
        expect(palette.b.a, 1);
        expect(palette.i.a, 1);
        expect(palette.j.a, 1);
        expect(palette.tile != null, level.darkTile);
        expect(palette.tgD != null, level.darkTile);
        if (level.darkTile) {
          expect(palette.tile, hasLength(2));
          expect(palette.tgD!.length, greaterThanOrEqualTo(2));
          expect(LevelTokens.tileColors(level.tier), hasLength(2));
        }
      }
    }
    final misty = LevelPalette.forStyle(AppearanceStyle.misty, 'sapph');
    expect(misty.a, const Color(0xFF97C6FF));
    expect(misty.b, const Color(0xFF2D68D6));
    expect(misty.i, const Color(0xFF1F5DB5));
    expect(misty.j, const Color(0xFF8DBEFF));
    final cinnabar = LevelPalette.forStyle(AppearanceStyle.cinnabar, 'gold');
    expect(cinnabar.a, const Color(0xFFFFF0B8));
    expect(cinnabar.b, const Color(0xFFDDA238));
    expect(cinnabar.tile, const [Color(0xFF382B17), Color(0xFF0D0A06)]);
    expect(cinnabar.tgD, const [
      Color(0xFFFFF4CC),
      Color(0xFFF2C35A),
      Color(0xFFC1861F),
    ]);
    expect(cinnabar.glow, const Color.fromRGBO(230, 176, 70, .6));
  });
}
