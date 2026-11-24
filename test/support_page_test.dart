import 'dart:math' as math;
import 'dart:ui' show SemanticsAction;

import 'package:chh_app/design/theme.dart';
import 'package:chh_app/pages/support_page.dart';
import 'package:chh_app/support/support_actions.dart';
import 'package:chh_app/support/support_badge_painter.dart';
import 'package:chh_app/support/support_badge_stage.dart';
import 'package:chh_app/ui/press.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_android/url_launcher_android.dart';

const _motion = MethodChannel('chh/motion');
const _support = MethodChannel('chh/support');
const _launcher = BasicMessageChannel<Object?>(
  'dev.flutter.pigeon.url_launcher_android.UrlLauncherApi.launchUrl',
  StandardMessageCodec(),
);

void main() {
  setUpAll(UrlLauncherAndroid.registerWith);

  testWidgets(
    'portrait and landscape expose the support copy, actions and semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final bridge = _Bridge(tester);
      await bridge.open(reduced: true);
      expect(find.text('每一份支持，都算数'), findsOneWidget);
      expect(find.text('金额随意，谢谢你喜欢 Chhers。'), findsOneWidget);
      expect(find.text('用支付宝支持'), findsOneWidget);
      expect(find.text('保存两张收款码'), findsOneWidget);
      final badge = tester.getSemantics(
        find.bySemanticsLabel(SupportBadgeStage.semanticsLabel),
      );
      expect(badge.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      expect(
        badge.getSemanticsData().hasAction(SemanticsAction.longPress),
        isTrue,
      );
      semantics.dispose();

      tester.view.physicalSize = const Size(844, 390);
      await tester.pump();
      await _until(tester, () => _visuals(tester).sprites != null);
      final cardBounds = tester
          .widget<SupportBadgeStage>(find.byType(SupportBadgeStage))
          .restingCard;
      final pay = tester.getRect(find.text('用支付宝支持'));
      expect(cardBounds.right, lessThan(pay.left));
      expect(pay.bottom, lessThan(390));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Alipay launches the exact external URI and offers a local save on failure',
    (tester) async {
      final bridge = _Bridge(tester)..launchAlipay = false;
      await bridge.open(reduced: true);
      await tester.tap(find.text('用支付宝支持'));
      await _advance(tester, const Duration(milliseconds: 400));
      expect(bridge.launches.single, [
        'alipays://platformapi/startapp?saId=10000007&qrcode='
            'https%3A%2F%2Fqr.alipay.com%2Ffkx1985781l1ncdyp1jkfaf',
        <String, String>{},
        false,
      ]);
      expect(find.text('没有找到支付宝'), findsOneWidget);
      await tester.tap(find.text('保存收款码'));
      await _until(tester, () => bridge.saves.length == 1);
      expect(bridge.saves.single, 'Chhers-alipay.png');
      await _advance(tester, const Duration(seconds: 2));
    },
  );

  testWidgets('the save button saves two PNGs and the toast opens WeChat', (
    tester,
  ) async {
    final bridge = _Bridge(tester);
    await bridge.open(reduced: true);
    await tester.tap(find.text('保存两张收款码'));
    await _until(tester, () => bridge.saves.length == 2);
    await _advance(tester, const Duration(milliseconds: 400));
    expect(bridge.saves, ['Chhers-alipay.png', 'Chhers-wechat.png']);
    expect(find.text('已保存到相册'), findsOneWidget);
    await tester.tap(find.text('打开微信'));
    await tester.pump();
    expect(bridge.weChatLaunches, 1);
  });

  testWidgets(
    'physical tap flips and each 400 ms hold saves the outward face',
    (tester) async {
      final bridge = _Bridge(tester);
      await bridge.open();
      await _advance(tester, const Duration(seconds: 12));
      final card = _visuals(tester).badge.card;
      expect(card.yaw.abs(), lessThan(.05));

      var gesture = await tester.startGesture(Offset(card.x, card.y));
      await tester.pump(const Duration(milliseconds: 399));
      expect(bridge.saves, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      await gesture.up();
      await _until(tester, () => bridge.saves.length == 1);
      expect(bridge.saves.single, 'Chhers-alipay.png');
      await _advance(tester, const Duration(milliseconds: 300));
      expect(find.text('已保存支付宝收款码'), findsOneWidget);

      await tester.tapAt(Offset(card.x + 24, card.y));
      await _advance(tester, const Duration(milliseconds: 1400));
      expect(card.yaw, closeTo(math.pi, .06));
      gesture = await tester.startGesture(Offset(card.x, card.y));
      await tester.pump(const Duration(milliseconds: 400));
      await gesture.up();
      await _until(tester, () => bridge.saves.length == 2);
      expect(bridge.saves.last, 'Chhers-wechat.png');
      await tester.pump();
      expect(find.text('已保存微信收款码'), findsOneWidget);
      final button = find.ancestor(
        of: find.text('打开微信'),
        matching: find.byType(PressScale),
      );
      expect(
        find.descendant(
          of: button,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is DecoratedBox &&
                widget.decoration is BoxDecoration &&
                (widget.decoration as BoxDecoration).color ==
                    SupportCode.weChat.ink,
          ),
        ),
        findsOneWidget,
      );
      await _advance(tester, const Duration(seconds: 4));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'reduced motion stays at rest, ignores dragging and fades the flip',
    (tester) async {
      final bridge = _Bridge(tester);
      await bridge.open(reduced: true);
      final visuals = _visuals(tester);
      final card = visuals.badge.card;
      final position = Offset(card.x, card.y);
      await tester.dragFrom(position, const Offset(55, -65));
      await tester.pump();
      expect(Offset(card.x, card.y), position);
      expect(card.yaw, 0);
      expect(bridge.motionCalls, isEmpty);
      expect(tester.binding.transientCallbackCount, 0);

      await tester.tapAt(position);
      await tester.pump();
      expect(card.yaw, math.pi);
      expect(Offset(card.x, card.y), position);
      expect(visuals.fade, lessThan(1));
      await _advance(tester, const Duration(milliseconds: 150));
      expect(visuals.fade, 1);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets(
    'portrait reacts to dragging, sleeps, wakes for motion and stops on return',
    (tester) async {
      final bridge = _Bridge(tester);
      await bridge.open();
      expect(bridge.motionCalls, ['listen']);
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await _advance(tester, const Duration(seconds: 12));
      expect(tester.binding.transientCallbackCount, 0);

      await bridge.emitMotion(ax: 2, ay: 9);
      await tester.pump();
      expect(tester.binding.transientCallbackCount, greaterThan(0));

      final card = _visuals(tester).badge.card;
      final center = Offset(card.x, card.y);
      final gesture = await tester.startGesture(center);
      await gesture.moveBy(const Offset(50, -50));
      await _advance(tester, const Duration(milliseconds: 250));
      expect((Offset(card.x, card.y) - center).distance, greaterThan(12));
      await gesture.up();
      expect(card.vx.abs() + card.vy.abs() + card.va.abs(), greaterThan(0));

      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(find.byType(SupportPage), findsNothing);
      expect(bridge.motionCalls, ['listen', 'cancel']);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets('background, covered route and TickerMode each cancel motion', (
    tester,
  ) async {
    final bridge = _Bridge(tester);
    await bridge.open();
    // Let the shared route spring finish while the badge is still dropping.
    await _advance(tester, const Duration(seconds: 1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(bridge.motionCalls, ['listen', 'cancel']);
    expect(tester.binding.transientCallbackCount, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(bridge.motionCalls.last, 'listen');

    bridge.tickerMode.value = false;
    await tester.pump();
    expect(bridge.motionCalls.last, 'cancel');
    expect(tester.binding.transientCallbackCount, 0);
    bridge.tickerMode.value = true;
    await tester.pump();
    expect(bridge.motionCalls.last, 'listen');

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    final covering = navigator.push<void>(
      MaterialPageRoute(builder: (_) => const Scaffold(body: Text('covered'))),
    );
    await tester.pumpAndSettle();
    expect(bridge.motionCalls.last, 'cancel');
    expect(tester.binding.transientCallbackCount, 0);
    navigator.pop();
    await covering;
    await _advance(tester, const Duration(milliseconds: 400));
    expect(bridge.motionCalls.last, 'listen');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

SupportBadgeVisuals _visuals(WidgetTester tester) {
  final widget = tester.widget<CustomPaint>(
    find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint && widget.painter is SupportBadgePainter,
    ),
  );
  return (widget.painter! as SupportBadgePainter).visuals;
}

Future<void> _advance(WidgetTester tester, Duration duration) async {
  for (var elapsed = Duration.zero; elapsed < duration;) {
    final tick = Duration(
      milliseconds: math.min(50, (duration - elapsed).inMilliseconds),
    );
    await tester.pump(tick);
    elapsed += tick;
  }
}

Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 80 && !done(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(done(), isTrue);
}

class _Bridge {
  _Bridge(this.tester) {
    messenger
      ..setMockMethodCallHandler(_motion, (call) async {
        motionCalls.add(call.method);
        return null;
      })
      ..setMockMethodCallHandler(_support, (call) async {
        if (call.method == 'openWeChatScan') {
          weChatLaunches++;
          return 'scan';
        }
        expect(call.method, 'saveImage');
        final args = call.arguments as Map<Object?, Object?>;
        final bytes = args['bytes'] as Uint8List;
        expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
        saves.add(args['displayName'] as String);
        return true;
      })
      ..setMockDecodedMessageHandler(_launcher, (message) async {
        launches.add(message);
        return [launchAlipay];
      });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    addTearDown(() {
      messenger
        ..setMockMethodCallHandler(_motion, null)
        ..setMockMethodCallHandler(_support, null)
        ..setMockDecodedMessageHandler(_launcher, null);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tickerMode.dispose();
    });
  }

  final WidgetTester tester;
  final tickerMode = ValueNotifier(true);
  final motionCalls = <String>[];
  final saves = <String>[];
  final launches = <Object?>[];
  var weChatLaunches = 0;
  var launchAlipay = true;

  TestDefaultBinaryMessenger get messenger =>
      tester.binding.defaultBinaryMessenger;

  Future<void> open({bool reduced = false}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
          child: ValueListenableBuilder<bool>(
            valueListenable: tickerMode,
            builder: (_, enabled, navigator) =>
                TickerMode(enabled: enabled, child: navigator!),
            child: child,
          ),
        ),
        home: Builder(
          builder: (context) => GestureDetector(
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const SupportPage()),
            ),
            child: const ColoredBox(
              color: Colors.white,
              child: Center(child: Text('open')),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await _advance(tester, const Duration(milliseconds: 500));
    await _until(tester, () => _visuals(tester).sprites != null);
  }

  Future<void> emitMotion({required double ax, required double ay}) =>
      messenger.handlePlatformMessage(
        _motion.name,
        _motion.codec.encodeSuccessEnvelope({
          'ax': ax,
          'ay': ay,
          'az': 0.0,
          'gx': 0.0,
          'gy': 0.0,
          'gz': 0.0,
          'rotation': 0,
        }),
        null,
      );
}
