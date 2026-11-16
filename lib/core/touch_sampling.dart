import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Aligns Android touch positions with display frames without changing system settings.
class TouchSampling with WidgetsBindingObserver {
  TouchSampling({this.frames = 1})
    : assert(frames > 0),
      _binding = WidgetsBinding.instance {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    _installed = true;
    _previousEnabled = _binding.resamplingEnabled;
    _previousOffset = _binding.samplingOffset;
    _binding.resamplingEnabled = true;
    _binding.addObserver(this);
    _binding.pointerRouter.addGlobalRoute(_handlePointer);
    _updateOffset();
  }

  final int frames;
  final WidgetsBinding _binding;
  final _touches = <int>{};
  bool _installed = false;
  bool _pendingUpdate = false;
  late final bool _previousEnabled;
  late final Duration _previousOffset;

  void _updateOffset() {
    if (!_installed) return;
    // Moving the sampling time during a drag can move content backwards.
    if (_touches.isNotEmpty) {
      _pendingUpdate = true;
      return;
    }
    _pendingUpdate = false;
    final rate = _binding.platformDispatcher.implicitView?.display.refreshRate;
    final hz = rate != null && rate.isFinite && rate > 0 ? rate : 60.0;
    final micros = (Duration.microsecondsPerSecond * frames / hz).round();
    _binding.samplingOffset = Duration(microseconds: -math.max(1, micros));
  }

  void _handlePointer(PointerEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    if (event is PointerDownEvent) {
      _touches.add(event.pointer);
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _touches.remove(event.pointer);
      if (_touches.isEmpty && _pendingUpdate) _updateOffset();
    }
  }

  @override
  void didChangeMetrics() => _updateOffset();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _updateOffset();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _touches.clear();
    }
  }

  void dispose() {
    if (!_installed) return;
    _installed = false;
    _binding.removeObserver(this);
    _binding.pointerRouter.removeGlobalRoute(_handlePointer);
    _touches.clear();
    _binding.resamplingEnabled = _previousEnabled;
    _binding.samplingOffset = _previousOffset;
  }
}
