import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui' show FrameTiming;

import 'package:chh_app/core/display_refresh.dart';
import 'package:chh_app/core/frame_metrics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

FrameTiming frame({
  int start = 1,
  int build = 1000,
  int raster = 1000,
  int overhead = 0,
  int gap = 0,
}) => FrameTiming(
  vsyncStart: start,
  buildStart: start + overhead,
  buildFinish: start + overhead + build,
  rasterStart: start + overhead + build + gap,
  rasterFinish: start + overhead + build + gap + raster,
  rasterFinishWallTime: 0,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('retained raw frames stay chronological and expose severe stalls', () {
    final buffer = FrameMetricsBuffer(capacity: 3);
    buffer.addTimings([
      frame(start: 1),
      frame(start: 10000, build: 51000),
      frame(start: 20000, raster: 18000),
      frame(start: 30000),
    ]);
    final result = buffer.snapshot(includeFrames: true);
    expect((result['frames'] as List).map((f) => f['vsyncUs']), [
      10000,
      20000,
      30000,
    ]);
    expect(result['buildOrRasterOver50MsCount'], 1);
    expect(result['maxConsecutiveOverTwoBudgets'], 2);
    expect(result['sampleSpanMs'], 20);
    expect(buffer.snapshot().containsKey('frames'), isFalse);
  });
  tearDown(() {
    FrameMetrics.stop();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DisplayRefresh.channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'latency is separate from either pipeline stage missing 120Hz budget',
    () {
      final buffer = FrameMetricsBuffer();
      buffer.addTimings([
        frame(
          build: 5000,
          raster: 5000,
        ), // Smooth pipelined frame, >8.33ms latency.
        frame(
          start: 20000,
          build: 8333,
          raster: 1,
        ), // Exact microsecond boundary.
        frame(start: 40000, build: 8334, raster: 1),
        frame(start: 60000, build: 1000, raster: 9000),
      ]);
      final stats = buffer.snapshot();
      expect(stats['sampleCount'], 4);
      expect(stats['uiOverBudgetCount'], 1);
      expect(stats['rasterOverBudgetCount'], 1);
      expect(stats['buildOrRasterOverBudgetCount'], 2);
      expect(stats['totalSpanOverBudgetCount'], 4);
      expect(stats.containsKey('fps'), isFalse);
      expect((stats['ui'] as Map)['p95Ms'], 8.334);
      expect((stats['raster'] as Map)['maxMs'], 9.0);
    },
  );

  test(
    'bounded retention and nearest-rank percentiles cover retained frames only',
    () {
      final buffer = FrameMetricsBuffer(capacity: 3);
      buffer.addTimings([
        for (var n = 1; n <= 5; n++) frame(start: n, build: n * 1000),
      ]);
      final stats = buffer.snapshot();
      expect(stats['sampleCount'], 3);
      expect(stats['receivedFrameCount'], 5);
      expect(stats['evictedSampleCount'], 2);
      expect(stats.containsKey('droppedFrameCount'), isFalse);
      expect((stats['ui'] as Map)['p50Ms'], 4.0);
      expect((stats['ui'] as Map)['p99Ms'], 5.0);
    },
  );

  test('reset drops delayed batches from before the sampling boundary', () {
    final buffer = FrameMetricsBuffer(capacity: 3);
    buffer.addTimings([frame(start: 10, build: 50000)]);
    buffer.reset(afterVsyncMicros: 100);
    buffer.addTimings([
      frame(start: 90, build: 50000),
      frame(start: 100),
      frame(start: 101, build: 2000),
    ]);
    final stats = buffer.snapshot();
    expect(stats['sampleCount'], 1);
    expect(stats['receivedFrameCount'], 1);
    expect((stats['ui'] as Map)['maxMs'], 2.0);
    buffer.reset();
    expect((buffer.snapshot()['ui'] as Map)['p50Ms'], isNull);
  });

  test(
    'display channel reports requested and actual without claiming equality',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(DisplayRefresh.channel, (call) async {
            calls.add(call.method);
            return {
              'available': true,
              'requestedMode': {'id': 4, 'refreshRate': 120.0},
              'actualMode': {'id': 3, 'refreshRate': 90.0},
              'supportedModes': [
                {'id': 3, 'width': 1440, 'height': 3168, 'refreshRate': 90.0},
                {'id': 4, 'width': 1440, 'height': 3168, 'refreshRate': 120.0},
              ],
            };
          });
      final requested = await DisplayRefresh.requestPreferred();
      expect((requested['requestedMode'] as Map)['refreshRate'], 120.0);
      final actual = await DisplayRefresh.read();
      expect((actual['actualMode'] as Map)['refreshRate'], 90.0);
      expect(calls, ['requestPreferred', 'read']);
    },
  );

  test(
    'unsupported platform and absent native plugin fall back safely',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect((await DisplayRefresh.read())['available'], false);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(
        (await DisplayRefresh.read())['reason'],
        'native-channel-unavailable',
      );
    },
  );

  test(
    'service handler exports JSON read/reset and rejects invalid actions',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      FrameMetrics.install(enabled: true);
      FrameMetrics.install(
        enabled: true,
      ); // Idempotent registration/callback setup.
      final read = await FrameMetrics.handleServiceExtension(
        FrameMetrics.extensionName,
        {'action': 'read'},
      );
      final data = jsonDecode(read.result!) as Map;
      expect(data['enabled'], true);
      expect(data['sampleCount'], 0);
      expect(data['display']['available'], false);
      final reset = await FrameMetrics.handleServiceExtension(
        FrameMetrics.extensionName,
        {'action': 'reset'},
      );
      expect(jsonDecode(reset.result!)['sampleCount'], 0);
      final invalid = await FrameMetrics.handleServiceExtension(
        FrameMetrics.extensionName,
        {'action': 'fps'},
      );
      expect(
        invalid.errorCode,
        developer.ServiceExtensionResponse.invalidParams,
      );
      expect(
        FrameMetrics.enabledByDefault,
        false,
      ); // Widget tests are debug, not profile.
    },
  );
}
