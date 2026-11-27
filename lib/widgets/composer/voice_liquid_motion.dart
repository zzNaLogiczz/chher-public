import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../design/composer_tokens.dart';
import '../../design/motion.dart';
import '../../design/voice_tokens.dart';
import 'dictation_controller.dart';
import 'voice_fly_motion.dart';
import 'voice_goo_motion.dart';

typedef _T = VoiceTokens;

typedef VoiceRipple = ({double x, double time, double amplitude, double speed});

typedef VoiceLiquidFrame = ({
  DictationPhase phase,
  double spread,
  double origin,
  double volume,
  double time,
  double flow,
  double opacity,
  double labels,
  double pull,
  bool detached,
  bool reduced,
});

/// The visual clock is independent of the recognition clock. It advances only
/// while the bar is visible and never changes a dictation phase.
class VoiceLiquidMotion extends ChangeNotifier {
  VoiceLiquidMotion([this._seed = _T.randomSeed]) {
    goo = VoiceGooMotion(_ripple, _random);
  }

  int _seed;
  double _time = 0;
  double _spread = 0, _speed = 0;
  double _volume = 0, _volumeSpeed = 0, _input = 0, _previousInput = 0;
  double _sampledAt = double.negativeInfinity;
  double _lastRipple = double.negativeInfinity;
  double _flow = 0, _origin = 0;
  double? _finger;
  double _reducedOpacity = 0, _labels = 0;
  bool _listening = false, _reduced = false;
  double _pull = 0;
  bool _detached = false;
  DictationPhase _phase = DictationPhase.idle;
  final _ripples = <VoiceRipple>[];
  late final VoiceGooMotion goo;
  double _width = 0;
  double? _fingerY, _labelFloor;
  bool _retracting = false;
  double? _cancelElapsed;
  bool _holdingForFly = false;
  int _nextGulp = 0;
  List<double> _arrivals = const [];
  double _popAt = 0;

  bool get retractionComplete => _retracting && !goo.retracting;
  bool get holdingForFly => _holdingForFly;
  double? get cancelElapsed => _cancelElapsed;
  double? get flyElapsed => _holdingForFly ? _cancelElapsed : null;
  double get _fadeSeconds =>
      AppMotion.reducedFade.inMicroseconds / Duration.microsecondsPerSecond;
  double get _undoSeconds =>
      _T.plainUndo.inMicroseconds / Duration.microsecondsPerSecond;
  double get dropOpacity => _reduced && _holdingForFly
      ? (1 - (_cancelElapsed ?? 0) / _fadeSeconds).clamp(0.0, 1.0)
      : 1;

  static double heightFor(VoiceLiquidFrame frame) {
    final progress = frame.reduced ? 1.0 : frame.spread.clamp(0.0, 1.0);
    return ComposerTokens.capsuleHeight +
        (_T.barHeight - ComposerTokens.capsuleHeight) * progress +
        (frame.reduced ? 0 : _T.heightGain * frame.volume * progress);
  }

  double get _top => (_T.barHeight - heightFor(frame)) / 2;
  bool get _expanded => _listening || _holdingForFly;

  void resize(double width) => _width = width;

  // Horizontal positions are relative to the bar center so the previous
  // capsule's RenderBox can provide the touch origin before layout expands.
  List<VoiceRipple> get ripples => _ripples;
  VoiceLiquidFrame get frame => (
    phase: _phase,
    spread: _spread,
    origin: _origin,
    volume: math.min(_T.maxVolume, _volume),
    time: _time,
    flow: _flow,
    opacity: _reduced
        ? _reducedOpacity
        : (_spread * _T.liquidFadeGain).clamp(0.0, 1.0),
    labels: _labels * _T.labelsOpacity,
    pull: _pull,
    detached: _detached,
    reduced: _reduced,
  );

  bool get needsTick {
    final cancelPending =
        _holdingForFly ||
        (_cancelElapsed != null &&
            _cancelElapsed! < (_reduced ? _fadeSeconds : _undoSeconds));
    return cancelPending ||
        _retracting ||
        (_reduced
            ? _reducedOpacity != (_expanded ? 1 : 0)
            : _expanded ||
                  _spread != 0 ||
                  _speed != 0 ||
                  _volume > _T.settleVolume ||
                  _volumeSpeed.abs() > _T.settleVolume ||
                  goo.busy);
  }

  void setReduced(bool reduced) {
    if (_reduced == reduced) return;
    _reduced = reduced;
    if (reduced) {
      _reducedOpacity = frame.spread.clamp(0.0, 1.0);
      _spread = _expanded ? 1 : 0;
      _speed = _volume = _volumeSpeed = _flow = 0;
      _ripples.clear();
      if (!_holdingForFly) {
        goo.clear(immediate: true);
        _stepGoo(0);
      }
    }
    notifyListeners();
  }

  void update({
    required DictationPhase phase,
    required bool listening,
    required double volume,
    required double? finger,
    required double pull,
    required bool detached,
    double width = 0,
    double? fingerY,
    double? labelFloor,
    bool retracting = false,
    bool holdBar = false,
    int flyCount = 0,
  }) {
    final starting = listening && !_listening;
    final canceling = phase == DictationPhase.canceling && phase != _phase;
    final pullChanged =
        pull != _pull ||
        finger != _finger ||
        fingerY != _fingerY ||
        detached != _detached;
    final dropEdge = detached != _detached;
    final wasRetracting = _retracting;
    final oldPhase = _phase;
    if (starting) {
      if (oldPhase == DictationPhase.canceling || _cancelElapsed != null) {
        _spread = _speed = _labels = _reducedOpacity = 0;
        _volume = _volumeSpeed = 0;
      }
      goo.clear(immediate: true);
      _origin = finger ?? 0;
      _input = _T.initialVolume;
      _previousInput = 0;
      _sampledAt = double.negativeInfinity;
      _lastRipple = _time;
      _ripples.clear();
      if (!_reduced) {
        _ripple(_origin, _T.firstRippleAmplitude, _T.firstRippleSpeed);
      }
    }
    if (!starting || volume > 0) {
      _input = listening ? volume.clamp(0.0, _T.maxVolume) : 0;
    }
    _phase = phase;
    _listening = listening;
    _width = width;
    _labelFloor = labelFloor;
    if (finger != null || (!retracting && !holdBar)) _finger = finger;
    if (fingerY != null) _fingerY = fingerY;
    _pull = pull;
    _detached = detached;
    _retracting = retracting;

    if (phase != DictationPhase.canceling) {
      _cancelElapsed = null;
      _holdingForFly = false;
    }
    if (canceling) {
      _cancelElapsed = 0;
      if (holdBar) {
        _stepGoo(0, follow: true);
        goo.holdForFly();
        _holdingForFly = true;
        _arrivals = voiceFlyArrivals(flyCount).toList();
        _nextGulp = 0;
        _popAt = voiceFlyPopTime(flyCount);
      }
    }
    if (retracting && !wasRetracting) {
      _stepGoo(0, follow: true);
      if (!_reduced) goo.retract();
    } else if (listening && (dropEdge || (_reduced && pullChanged))) {
      _stepGoo(0);
    } else if (!listening && !_holdingForFly && oldPhase != phase) {
      goo.clear();
    }
    if (_reduced) {
      _spread = _expanded ? 1 : 0;
      if (pullChanged) notifyListeners();
    }
  }

  void advance(double elapsed) {
    final dt = _reduced ? elapsed : elapsed.clamp(0.0, _T.maxStep);
    if (!_reduced) _time += dt;
    if (_cancelElapsed != null) {
      _cancelElapsed = _cancelElapsed! + dt;
      if (_holdingForFly) {
        if (!_reduced) {
          while (_nextGulp < _arrivals.length &&
              _cancelElapsed! >= _arrivals[_nextGulp]) {
            goo.gulp();
            _nextGulp++;
          }
        }
        if (_cancelElapsed! >= (_reduced ? _fadeSeconds : _popAt)) {
          goo.pop(_time, reduced: _reduced);
          if (_reduced) goo.dismissRed();
          _holdingForFly = false;
          _origin = 0;
        }
      }
    }
    final target = _expanded ? 1.0 : 0.0;
    if (_reduced) {
      final delta = elapsed / _fadeSeconds;
      _reducedOpacity = _toward(_reducedOpacity, target, delta);
      _labels = _reducedOpacity;
      notifyListeners();
      return;
    }
    if (_listening && _time - _sampledAt > _T.volumeSampleInterval) {
      _sampledAt = _time;
      if (_input > _T.accentThreshold &&
          _input >= _previousInput &&
          _time - _lastRipple >= _T.accentInterval) {
        _lastRipple = _time;
        _ripple(
          _finger ?? (_random() - .5) * _T.handsFreeRippleRange,
          _T.accentRippleBase + _T.accentRippleGain * _input,
          _T.accentRippleSpeed,
        );
      }
      _previousInput = _input;
    }
    _volumeSpeed +=
        (_T.volumeStiffness * (_input - _volume) -
            _T.volumeDamping * _volumeSpeed) *
        dt;
    _volume = (_volume + _volumeSpeed * dt).clamp(0.0, _T.maxEnvelope);
    _speed +=
        (_T.spreadStiffness * (target - _spread) - _T.spreadDamping * _speed) *
        dt;
    _spread += _speed * dt;
    if ((target - _spread).abs() < _T.settleSpread &&
        _speed.abs() < _T.settleVelocity) {
      _spread = target;
      _speed = 0;
    }
    final showLabels = _expanded && _spread > _T.labelsRevealAt;
    final labelDuration = showLabels ? _T.labelsIn : _T.labelsOut;
    _labels = _toward(
      _labels,
      showLabels ? 1 : 0,
      dt * Duration.microsecondsPerSecond / labelDuration.inMicroseconds,
    );
    _flow +=
        dt *
        (_T.liquidSpeed + _T.liquidSpeedGain * math.min(_T.maxVolume, _volume));
    _ripples.removeWhere((ripple) => _time - ripple.time >= _T.rippleLifetime);
    _stepGoo(dt);
    if (!_expanded && _spread < _T.redDismissSpread) goo.dismissRed();
    notifyListeners();
  }

  void _stepGoo(double dt, {bool? follow}) {
    if (_width <= 0) return;
    goo.step(
      dt: dt,
      time: _time,
      width: _width,
      top: _top,
      finger: _finger ?? 0,
      fingerY: _fingerY,
      labelFloor: _labelFloor,
      pull: _pull,
      follow: follow ?? (_listening && _finger != null && !_retracting),
      detached: _detached,
      reduced: _reduced,
    );
  }

  static double _toward(double value, double target, double delta) =>
      target > value
      ? math.min(target, value + delta)
      : math.max(target, value - delta);

  void _ripple(double x, double amplitude, double speed) =>
      _ripples.add((x: x, time: _time, amplitude: amplitude, speed: speed));

  double _random() {
    _seed = (_seed + _T.randomStep) & _T.randomMask;
    var mixed =
        ((_seed ^ (_seed >>> _T.randomSeedShift)) * (1 | _seed)) &
        _T.randomMask;
    mixed =
        ((mixed +
                ((mixed ^ (mixed >>> _T.randomMixShift)) *
                    (_T.randomMix | mixed))) ^
            mixed) &
        _T.randomMask;
    return ((mixed ^ (mixed >>> _T.randomFinalShift)) & _T.randomMask) /
        _T.randomRange;
  }
}
