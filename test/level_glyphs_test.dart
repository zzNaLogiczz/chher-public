import 'dart:ui';

import 'package:chh_app/design/level_glyphs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('relative arcs form the approved circular silhouette', () {
    final path = parseLevelPath('M12 8.4a6 6 0 1 0 0 12a6 6 0 1 0 0-12Z');
    final bounds = path.getBounds();
    expect(bounds.left, closeTo(6, .001));
    expect(bounds.top, closeTo(8.4, .001));
    expect(bounds.right, closeTo(18, .001));
    expect(bounds.bottom, closeTo(20.4, .001));
  });

  test('relative quadratic and cubic points use each segment origin', () {
    final path = parseLevelPath('M10 10q5-10 10 0c5 10 10 10 15 0');
    expect(path.getBounds(), const Rect.fromLTRB(10, 0, 35, 20));
    final absolute = parseLevelPath('M10 10Q15 0 20 10C25 20 30 20 35 10');
    expect(path.getBounds(), absolute.getBounds());
  });

  test('implicit lines, horizontal, vertical and close restore the origin', () {
    final path = parseLevelPath('M2 3 8 3h2v7H2V3zl-1-1');
    expect(path.getBounds(), const Rect.fromLTRB(1, 2, 10, 10));
  });

  test('absolute arcs and smooth cubic controls retain their bounds', () {
    expect(
      parseLevelPath('M2 2C2 0 4 0 4 2s2 2 2 0S8 0 8 2').getBounds(),
      const Rect.fromLTRB(2, 0, 8, 4),
    );
    final arc = parseLevelPath('M0 5A5 5 0 0 1 10 5');
    expect(arc.getBounds().left, closeTo(0, .001));
    expect(arc.getBounds().right, closeTo(10, .001));
    expect(arc.getBounds().height, closeTo(5, .001));
  });

  test('every approved glyph parses and is cached', () {
    expect(levelGlyphSources, hasLength(16));
    for (final key in levelGlyphSources.keys) {
      final glyph = LevelGlyphs.get(key);
      expect(identical(glyph, LevelGlyphs.get(key)), isTrue);
      for (final path in [glyph.f, glyph.s, glyph.d].nonNulls) {
        expect(path.getBounds().isFinite, isTrue, reason: key);
        expect(path.getBounds().isEmpty, isFalse, reason: key);
      }
    }
    const source = 'M0 0L5 5';
    expect(identical(parseLevelPath(source), parseLevelPath(source)), isTrue);
  });

  test('four-point star follows the prototype formula', () {
    final bounds = parseLevelPath(levelStar4(12, 12, 9.6)).getBounds();
    expect(bounds.left, closeTo(2.4, .001));
    expect(bounds.top, closeTo(2.4, .001));
    expect(bounds.right, closeTo(21.6, .001));
    expect(bounds.bottom, closeTo(21.6, .001));
  });

  test('incomplete and unsupported commands fail instead of looping', () {
    expect(() => parseLevelPath('M0'), throwsFormatException);
    expect(() => parseLevelPath('M0 0T1 1'), throwsFormatException);
    expect(() => parseLevelPath('M0 0A2 2 0 2 0 4 0'), throwsFormatException);
  });
}
