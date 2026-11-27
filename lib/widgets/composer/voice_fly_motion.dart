import 'dart:math' as math;

import '../../design/voice_text_tokens.dart';

typedef _T = VoiceTextTokens;

int _groupSize(int count) => math.max(1, (count / _T.flyGroups).ceil());

int voiceFlyGroup(int index, int count) =>
    _T.flyGroups - 1 - index ~/ _groupSize(count);

double voiceFlyDelay(int index, int count) =>
    voiceFlyGroup(index, count) * _T.flyGroupStagger +
    index % _groupSize(count) * _T.flyGlyphStagger;

/// In group order, when the last glyph in each occupied group reaches the drop.
Iterable<double> voiceFlyArrivals(int count) sync* {
  final per = _groupSize(count);
  for (var end = count; end > 0; end = (end - 1) ~/ per * per) {
    yield voiceFlyDelay(end - 1, count) + _T.flyDuration;
  }
}

double voiceFlyPopTime(int count) => count == 0
    ? _T.flyEmptyDelay
    : voiceFlyArrivals(count).reduce(math.max) + _T.flyPopDelay;

({double x, double y, double rotation, double scale, double opacity})
voiceFlyPose({
  required double elapsed,
  required double delay,
  required double x0,
  required double y0,
  required double x2,
  required double y2,
  required double side,
  required double bend,
  required double rotation,
}) {
  final p = ((elapsed - delay) / _T.flyDuration).clamp(0.0, 1.0);
  final e = math.pow(p, _T.flyAcceleration).toDouble();
  final dx = x2 - x0, dy = y2 - y0;
  final distance = math.sqrt(dx * dx + dy * dy);
  final normal = side * bend / (distance == 0 ? 1 : distance);
  final cx = (x0 + x2) / 2 - dy * normal;
  final cy = (y0 + y2) / 2 + dx * normal - _T.flyLift;
  final t = 1 - e;
  return (
    x: t * t * x0 + 2 * t * e * cx + e * e * x2,
    y: t * t * y0 + 2 * t * e * cy + e * e * y2,
    rotation: rotation * e * math.pi / 180,
    scale: 1 - _T.flyScaleLoss * e,
    opacity: p < _T.flyFadeStart ? 1 : (1 - p) / (1 - _T.flyFadeStart),
  );
}
