/// Bounded frame timings. Work per delivered frame is one ring-buffer write;
/// sorting/aggregation happens only on an explicit service-extension read.
library;

import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'display_refresh.dart';

/// Statistics cover retained frames, never wall-clock idle time or invented FPS.
class FrameMetricsBuffer {
  final int capacity;
  final double budgetHz;
  final List<FrameTiming?> _ring;
  int _next = 0;
  int _length = 0;
  int _received = 0;
  int _minimumVsyncMicros = -1;

  FrameMetricsBuffer({this.capacity = 6000, this.budgetHz = 120})
    : assert(capacity > 0),
      assert(budgetHz > 0),
      _ring = List<FrameTiming?>.filled(capacity, null);

  void addTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      // Reports are batched. Discard frames produced before a reset but
      // delivered afterwards, so an old screen cannot pollute a new sample.
      if (timing.timestampInMicroseconds(FramePhase.vsyncStart) <=
          _minimumVsyncMicros) {
        continue;
      }
      _ring[_next] = timing;
      _next = (_next + 1) % capacity;
      if (_length < capacity) _length++;
      _received++;
    }
  }

  void reset({int afterVsyncMicros = -1}) {
    _ring.fillRange(0, capacity, null);
    _next = 0;
    _length = 0;
    _received = 0;
    _minimumVsyncMicros = afterVsyncMicros;
  }

  Map<String, Object?> snapshot({bool includeFrames = false}) {
    final ui = <int>[];
    final raster = <int>[];
    final total = <int>[];
    final budgetMicros = 1000000 / budgetHz;
    var buildOrRasterOverBudget = 0;
    var over50Ms = 0;
    var consecutive = 0;
    var maxConsecutive = 0;
    final ordered = [
      for (var i = 0; i < _length; i++)
        _ring[(_next - _length + capacity + i) % capacity]!,
    ];
    for (final timing in ordered) {
      final buildUs = timing.buildDuration.inMicroseconds;
      final rasterUs = timing.rasterDuration.inMicroseconds;
      ui.add(buildUs);
      raster.add(rasterUs);
      total.add(timing.totalSpan.inMicroseconds);
      if (buildUs > budgetMicros || rasterUs > budgetMicros) {
        buildOrRasterOverBudget++;
      }
      if (buildUs > 50000 || rasterUs > 50000) over50Ms++;
      consecutive = buildUs > budgetMicros * 2 || rasterUs > budgetMicros * 2
          ? consecutive + 1
          : 0;
      maxConsecutive = math.max(maxConsecutive, consecutive);
    }
    final uiStats = _statistics(ui, budgetMicros);
    final rasterStats = _statistics(raster, budgetMicros);
    final totalStats = _statistics(total, budgetMicros);
    return {
      'sampleCount': _length,
      'receivedFrameCount': _received,
      'evictedSampleCount': _received - _length,
      'capacity': capacity,
      'window': 'lastRetainedFramesSinceReset',
      'percentileMethod': 'nearest-rank',
      'budgetHz': budgetHz,
      'budgetMs': 1000 / budgetHz,
      'ui': uiStats,
      'raster': rasterStats,
      'totalSpan': totalStats,
      'uiOverBudgetCount': uiStats['overBudgetCount'],
      'rasterOverBudgetCount': rasterStats['overBudgetCount'],
      'buildOrRasterOverBudgetCount': buildOrRasterOverBudget,
      'buildOrRasterOver50MsCount': over50Ms,
      'maxConsecutiveOverTwoBudgets': maxConsecutive,
      'sampleSpanMs': ordered.length < 2
          ? 0
          : (ordered.last.timestampInMicroseconds(FramePhase.vsyncStart) -
                    ordered.first.timestampInMicroseconds(
                      FramePhase.vsyncStart,
                    )) /
                1000,
      if (includeFrames)
        'frames': [
          for (final frame in ordered)
            {
              'vsyncUs': frame.timestampInMicroseconds(FramePhase.vsyncStart),
              'buildUs': frame.buildDuration.inMicroseconds,
              'rasterUs': frame.rasterDuration.inMicroseconds,
              'rasterFinishUs': frame.timestampInMicroseconds(
                FramePhase.rasterFinish,
              ),
            },
        ],
      'totalSpanOverBudgetCount': totalStats['overBudgetCount'],
      'totalSpanIsLatency': true,
    };
  }

  Map<String, Object?> _statistics(List<int> micros, double budgetMicros) {
    micros.sort();
    double? percentile(double p) => micros.isEmpty
        ? null
        : micros[math.max(0, (micros.length * p).ceil() - 1)] / 1000;
    return {
      'p50Ms': percentile(.50),
      'p95Ms': percentile(.95),
      'p99Ms': percentile(.99),
      'maxMs': micros.isEmpty ? null : micros.last / 1000,
      'overBudgetCount': micros.where((v) => v > budgetMicros).length,
    };
  }
}

abstract final class FrameMetrics {
  static const extensionName = 'ext.chh.frameMetrics';
  static const enabledByDefault =
      kProfileMode ||
      bool.fromEnvironment('chh_frame_metrics', defaultValue: false);
  static final _buffer = FrameMetricsBuffer();
  static bool _enabled = false;
  static bool _registered = false;

  /// Call after WidgetsFlutterBinding.ensureInitialized(). No tracking or VM
  /// extension is installed in a normal release build.
  static void install({bool enabled = enabledByDefault}) {
    if (!enabled || _enabled) return;
    reset();
    SchedulerBinding.instance.addTimingsCallback(_buffer.addTimings);
    _enabled = true;
    if (!_registered) {
      developer.registerExtension(extensionName, handleServiceExtension);
      _registered = true;
    }
  }

  static void stop() {
    if (!_enabled) return;
    SchedulerBinding.instance.removeTimingsCallback(_buffer.addTimings);
    _enabled = false;
  }

  static Map<String, Object?> reset() {
    _buffer.reset(
      afterVsyncMicros:
          SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds,
    );
    return read();
  }

  static Map<String, Object?> read({bool includeFrames = false}) => {
    'enabled': _enabled,
    'buildMode': kProfileMode
        ? 'profile'
        : kReleaseMode
        ? 'release'
        : 'debug',
    ..._buffer.snapshot(includeFrames: includeFrames),
  };

  /// Service protocol: ext.chh.frameMetrics?isolateId=...&action=reset|read.
  /// JSON export runs on demand, never in the timing callback itself.
  @visibleForTesting
  static Future<developer.ServiceExtensionResponse> handleServiceExtension(
    String method,
    Map<String, String> parameters,
  ) async {
    final action = parameters['action'] ?? 'read';
    if (action == 'reset') {
      return developer.ServiceExtensionResponse.result(jsonEncode(reset()));
    }
    if (action == 'read') {
      final metrics = read(
        includeFrames: parameters['includeFrames'] == 'true',
      );
      final display = await DisplayRefresh.read();
      return developer.ServiceExtensionResponse.result(
        jsonEncode({...metrics, 'display': display}),
      );
    }
    if (action == 'display') {
      return developer.ServiceExtensionResponse.result(
        jsonEncode(await DisplayRefresh.read()),
      );
    }
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.invalidParams,
      jsonEncode({'message': 'action must be reset, read or display'}),
    );
  }
}
