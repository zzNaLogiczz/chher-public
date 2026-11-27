import 'dart:collection';
import 'dart:math' as math;

/// Tracks the ambient noise floor from raw audio frames during hands-free input.
class HandsFreeVolume {
  static const _minimumThreshold = .15;
  static const _noiseMargin = .15;
  static const _warmup = Duration(milliseconds: 500);
  static const _window = Duration(seconds: 3);
  static const _smoothingMicros = 300000;

  final Duration startedAt;
  // Increasing minima. A newer, quieter sample supersedes older louder ones.
  final _minima = Queue<({Duration at, double level})>();
  Duration? _lastAt;
  double _smoothed = 0;

  HandsFreeVolume(this.startedAt);

  bool hasVoice(Duration at, double level) {
    final lastAt = _lastAt;
    _lastAt = at;
    // Several 40 ms PCM frames can arrive in the same recorder callback.
    final dt = lastAt == null ? 0 : (at - lastAt).inMicroseconds;
    final weight = lastAt == null
        ? 1.0
        : 1 - math.exp(-(dt == 0 ? 40000 : dt) / _smoothingMicros);
    _smoothed += (level - _smoothed) * weight;
    while (_minima.isNotEmpty && at - _minima.first.at >= _window) {
      _minima.removeFirst();
    }
    while (_minima.isNotEmpty && _minima.last.level >= _smoothed) {
      _minima.removeLast();
    }
    _minima.addLast((at: at, level: _smoothed));
    final threshold = at - startedAt < _warmup
        ? _minimumThreshold
        : math.max(_minimumThreshold, _minima.first.level + _noiseMargin);
    return _smoothed >= threshold;
  }
}
