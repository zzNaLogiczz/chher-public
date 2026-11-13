import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motor/motor.dart';

import 'package:chh_app/design/motion.dart';
import 'package:chh_app/design/shapes.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/design/typography.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('tokens match the spec values', () {
    // 朱漆红 v2(设计稿 red-theme-2026-11-10 lacquer 方案)
    expect(AppTokens.light.bg, const Color(0xFFFFFDFC));
    expect(AppTokens.light.grouped, const Color(0xFFF6F3F1));
    expect(AppTokens.light.accent, const Color(0xFFAF2025));
    expect(AppTokens.light.lacTop, const Color(0xFFC62F2F));
    expect(AppTokens.light.lacBot, const Color(0xFF94151E));
    expect(AppTokens.light.unreadBg, const Color(0xFFFFF4F1));
    expect(AppTokens.dark.bg, const Color(0xFF0D0B0A));
    expect(AppTokens.dark.surface, const Color(0xFF1B1817));
    expect(AppTokens.dark.accent, const Color(0xFFEA857F));
    expect(AppTokens.dark.lacTop, const Color(0xFF7A201E));
    expect(AppTokens.dark.lacBot, const Color(0xFF4A1311));
    // 深色主按钮白字(v1 规则保留)
    expect(AppTokens.dark.onAccent, const Color(0xFFFFFFFF));
    expect(AppTokens.light.onAccent, const Color(0xFFFFFFFF));
    expect(
      AppTokens.light.background(AppSurface.grouped),
      AppTokens.light.grouped,
    );
  });

  test('text pairs meet 4.5:1 in both themes', () {
    for (final t in [AppTokens.light, AppTokens.dark]) {
      // 实心红按钮/选中底的白字(v2:主按钮走漆面渐变,不吃 accent)
      expect(contrast(t.onAccent, t.btnTop), greaterThanOrEqualTo(4.5));
      expect(contrast(t.onAccent, t.scoreBg), greaterThanOrEqualTo(4.5));
      expect(contrast(t.text2, t.bg), greaterThanOrEqualTo(4.5));
      expect(contrast(t.text2, t.surface), greaterThanOrEqualTo(4.5));
      expect(contrast(t.accent, t.bg), greaterThanOrEqualTo(4.5));
      // 漆面上的两级文字
      expect(contrast(t.onLac, t.lacBot), greaterThanOrEqualTo(4.5));
    }
  });

  test('type roles and springs match the spec', () {
    expect(
      [
        AppType.largeTitle,
        AppType.title1,
        AppType.title2,
        AppType.headline,
        AppType.body,
        AppType.callout,
        AppType.subhead,
        AppType.footnote,
        AppType.caption,
      ].map((s) => s.fontSize),
      [32, 26, 22, 17, 17, 16, 15, 13, 12],
    );
    expect(AppType.reading.height, 1.8);
    expect(AppType.readingLarge.fontSize, 20);
    expect(
      (AppMotion.tap.duration, AppMotion.tap.bounce),
      (const Duration(milliseconds: 250), 0.0),
    );
    expect(
      (AppMotion.select.duration, AppMotion.select.bounce),
      (const Duration(milliseconds: 340), 0.18),
    );
    expect(
      (AppMotion.reveal.duration, AppMotion.reveal.bounce),
      (const Duration(milliseconds: 380), 0.0),
    );
    expect(
      (AppMotion.sheet.duration, AppMotion.sheet.bounce),
      (const Duration(milliseconds: 420), 0.14),
    );
    expect(
      (AppMotion.pop.duration, AppMotion.pop.bounce),
      (const Duration(milliseconds: 300), 0.30),
    );
  });

  testWidgets('grouped card clipping preserves only its outer corners', (
    tester,
  ) async {
    for (final first in [false, true]) {
      for (final last in [false, true]) {
        final radius = BorderRadius.vertical(
          top: first ? const Radius.circular(AppRadii.md) : Radius.zero,
          bottom: last ? const Radius.circular(AppRadii.md) : Radius.zero,
        );
        await tester.pumpWidget(
          AppClip.borderRadius(
            borderRadius: radius,
            child: const SizedBox(width: 100, height: 44),
          ),
        );
        if (kContinuousCorners) {
          expect(
            tester
                .widget<ClipRSuperellipse>(find.byType(ClipRSuperellipse))
                .borderRadius,
            radius,
          );
        } else {
          expect(
            tester.widget<ClipRRect>(find.byType(ClipRRect)).borderRadius,
            radius,
          );
        }
      }
    }
  });

  testWidgets('reduced motion maps every spring to no motion', (tester) async {
    late Motion resolved;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Builder(
          builder: (c) {
            resolved = AppMotion.of(c, AppMotion.select);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(resolved, isA<NoMotion>());
  });
}
