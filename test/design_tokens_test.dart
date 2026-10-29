import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motor/motor.dart';

import 'package:chh_app/design/motion.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/design/typography.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('tokens match the spec values', () {
    expect(AppTokens.light.bg, const Color(0xFFFFFFFF));
    expect(AppTokens.light.grouped, const Color(0xFFF2F2F7));
    expect(AppTokens.light.surface, const Color(0xFFFFFFFF));
    expect(AppTokens.light.accent, const Color(0xFF0D74CE));
    expect(AppTokens.dark.bg, const Color(0xFF0B0B0C));
    expect(AppTokens.dark.surface, const Color(0xFF1C1C1E));
    expect(AppTokens.dark.accent, const Color(0xFF70B8FF));
    expect(AppTokens.dark.onAccent, const Color(0xFF0B0B0C));
    expect(
      AppTokens.light.background(AppSurface.grouped),
      AppTokens.light.grouped,
    );
  });

  test('text pairs meet 4.5:1 in both themes', () {
    for (final t in [AppTokens.light, AppTokens.dark]) {
      expect(contrast(t.onAccent, t.accent), greaterThanOrEqualTo(4.5));
      expect(contrast(t.text2, t.bg), greaterThanOrEqualTo(4.5));
      expect(contrast(t.text2, t.surface), greaterThanOrEqualTo(4.5));
      expect(contrast(t.accent, t.bg), greaterThanOrEqualTo(4.5));
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
