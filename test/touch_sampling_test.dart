import 'package:chh_app/core/touch_sampling.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  TouchSampling? sampling;
  late bool previousEnabled;
  late Duration previousOffset;

  setUp(() {
    previousEnabled = binding.resamplingEnabled;
    previousOffset = binding.samplingOffset;
  });

  tearDown(() {
    sampling?.dispose();
    sampling = null;
    binding.resamplingEnabled = previousEnabled;
    binding.samplingOffset = previousOffset;
    binding.platformDispatcher.implicitView?.display.resetRefreshRate();
  });

  testWidgets(
    'Android samples one actual display frame behind and follows rate changes',
    (tester) async {
      tester.view.display.refreshRate = 120;
      sampling = TouchSampling();
      expect(binding.resamplingEnabled, isTrue);
      expect(binding.samplingOffset, const Duration(microseconds: -8333));
      tester.view.display.refreshRate = 90;
      expect(binding.samplingOffset, const Duration(microseconds: -11111));
      tester.view.display.refreshRate = 60;
      expect(binding.samplingOffset, const Duration(microseconds: -16667));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'calibration supports a two-frame offset',
    (tester) async {
      tester.view.display.refreshRate = 120;
      sampling = TouchSampling(frames: 2);
      expect(binding.samplingOffset, const Duration(microseconds: -16667));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'invalid display rates fall back to 60Hz',
    (tester) async {
      sampling = TouchSampling();
      for (final rate in [0.0, -1.0, double.nan, double.infinity]) {
        tester.view.display.refreshRate = rate;
        expect(binding.samplingOffset, const Duration(microseconds: -16667));
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'metrics updates wait for every touch to end or cancel',
    (tester) async {
      tester.view.display.refreshRate = 120;
      sampling = TouchSampling();
      binding.pointerRouter.route(const PointerDownEvent(pointer: 1));
      binding.pointerRouter.route(const PointerDownEvent(pointer: 2));
      tester.view.display.refreshRate = 60;
      binding.pointerRouter.route(
        const PointerMoveEvent(pointer: 1, delta: Offset(0, 1)),
      );
      expect(binding.samplingOffset, const Duration(microseconds: -8333));
      binding.pointerRouter.route(const PointerUpEvent(pointer: 1));
      expect(binding.samplingOffset, const Duration(microseconds: -8333));
      tester.view.display.refreshRate = 90;
      binding.pointerRouter.route(const PointerCancelEvent(pointer: 2));
      expect(binding.samplingOffset, const Duration(microseconds: -11111));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'mouse input does not delay touch configuration',
    (tester) async {
      tester.view.display.refreshRate = 120;
      sampling = TouchSampling();
      binding.pointerRouter.route(
        const PointerDownEvent(pointer: 1, kind: PointerDeviceKind.mouse),
      );
      tester.view.display.refreshRate = 60;
      expect(binding.samplingOffset, const Duration(microseconds: -16667));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'resuming updates the offset after a cancelled background gesture',
    (tester) async {
      tester.view.display.refreshRate = 120;
      sampling = TouchSampling();
      binding.pointerRouter.route(const PointerDownEvent(pointer: 1));
      tester.view.display.refreshRate = 60;
      expect(binding.samplingOffset, const Duration(microseconds: -8333));
      sampling!.didChangeAppLifecycleState(AppLifecycleState.paused);
      sampling!.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(binding.samplingOffset, const Duration(microseconds: -16667));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'dispose removes listeners and restores previous sampling values',
    (tester) async {
      tester.view.display.refreshRate = 120;
      binding.resamplingEnabled = true;
      binding.samplingOffset = const Duration(milliseconds: -12);
      final routes = binding.pointerRouter.debugGlobalRouteCount;
      sampling = TouchSampling();
      expect(binding.pointerRouter.debugGlobalRouteCount, routes + 1);
      binding.pointerRouter.route(const PointerDownEvent(pointer: 1));
      tester.view.display.refreshRate = 60;
      sampling!.dispose();
      expect(binding.pointerRouter.debugGlobalRouteCount, routes);
      expect(binding.resamplingEnabled, isTrue);
      expect(binding.samplingOffset, const Duration(milliseconds: -12));
      tester.view.display.refreshRate = 90;
      binding.pointerRouter.route(const PointerUpEvent(pointer: 1));
      expect(binding.samplingOffset, const Duration(milliseconds: -12));
      sampling!.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'non-Android platforms keep their existing sampling configuration',
    (tester) async {
      binding.resamplingEnabled = false;
      binding.samplingOffset = const Duration(milliseconds: -9);
      final routes = binding.pointerRouter.debugGlobalRouteCount;
      sampling = TouchSampling();
      tester.view.display.refreshRate = 120;
      expect(binding.resamplingEnabled, isFalse);
      expect(binding.samplingOffset, const Duration(milliseconds: -9));
      expect(binding.pointerRouter.debugGlobalRouteCount, routes);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
