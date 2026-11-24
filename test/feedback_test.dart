import 'package:chh_app/widgets/chhers_loader.dart';
import 'dart:io';

import 'package:chh_app/design/icons.dart';
import 'package:chh_app/design/motion.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/ui/app_button.dart';
import 'package:chh_app/ui/feedback.dart';
import 'package:chh_app/ui/press.dart';
import 'package:chh_app/widgets/state_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child) => MaterialApp(
  theme: buildAppTheme(Brightness.light),
  home: Scaffold(body: child),
);

Future<BuildContext> toastContext(WidgetTester tester) async {
  await tester.pumpWidget(app(const SizedBox.expand()));
  return tester.element(find.byType(Scaffold));
}

double toastOpacity(WidgetTester tester, Finder message) => tester
    .widget<Opacity>(
      find.ancestor(of: message, matching: find.byType(Opacity)).first,
    )
    .opacity;

void main() {
  testWidgets('toast pops in near the top and leaves after 1.6s', (
    tester,
  ) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) {
            ctx = context;
            return const SizedBox.expand();
          },
        ),
      ),
    );
    AppToast.show(ctx, '已发送');
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('已发送'), findsOneWidget);
    expect(tester.getTopLeft(find.text('已发送')).dy, lessThan(120));
    await tester.pump(const Duration(milliseconds: 1100));
    expect(toastOpacity(tester, find.text('已发送')), closeTo(1, .001));
    await tester.pump(AppMotion.fade + const Duration(milliseconds: 1));
    expect(find.text('已发送'), findsNothing);
  });

  testWidgets('reducing motion preserves both toast lifetimes', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final context = await toastContext(tester);

    AppToast.show(context, '已发送');
    final plain = find.text('已发送');
    await tester.pump();
    await tester.pump();
    expect(toastOpacity(tester, plain), 1);
    await tester.pump(const Duration(milliseconds: 1500));
    expect(plain, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    expect(toastOpacity(tester, plain), closeTo(1, .001));
    await tester.pump(AppMotion.fade + const Duration(milliseconds: 1));
    expect(plain, findsNothing);

    AppToast.show(
      context,
      '已保存到相册',
      actionLabel: '打开微信',
      onAction: () => fail('An untouched action should never run'),
    );
    final action = find.text('打开微信');
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 5900));
    expect(toastOpacity(tester, action), 1);
    await tester.pump(const Duration(milliseconds: 101) + AppMotion.fade);
    expect(action, findsNothing);
  });

  testWidgets('a new toast replaces the previous one', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) {
            ctx = context;
            return const SizedBox.expand();
          },
        ),
      ),
    );
    AppToast.show(ctx, '第一条');
    await tester.pump(const Duration(milliseconds: 300));
    AppToast.show(ctx, '第二条');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('第一条'), findsNothing);
    expect(find.text('第二条'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });

  testWidgets('a toast can be replaced before its first frame', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) {
            ctx = context;
            return const SizedBox.expand();
          },
        ),
      ),
    );
    AppToast.show(ctx, '第一条');
    AppToast.show(ctx, '第二条');
    await tester.pump();
    expect(find.text('第一条'), findsNothing);
    expect(find.text('第二条'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('removing the overlay before a toast expires is safe', (
    tester,
  ) async {
    late BuildContext ctx;
    Widget host() => app(
      Builder(
        builder: (context) {
          ctx = context;
          return const SizedBox.expand();
        },
      ),
    );
    await tester.pumpWidget(host());
    AppToast.show(ctx, '要移除的提示');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('要移除的提示'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(host());
    AppToast.show(ctx, '新提示');
    await tester.pump();
    expect(find.text('新提示'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a toast action stays available and runs once', (tester) async {
    late BuildContext ctx;
    var taps = 0;
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) {
            ctx = context;
            return const SizedBox.expand();
          },
        ),
      ),
    );
    AppToast.show(ctx, '已保存到相册', actionLabel: '打开微信', onAction: () => taps++);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    final action = find.text('打开微信');
    expect(action, findsOneWidget);
    await tester.tap(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(action, findsNothing);
  });

  testWidgets('an untouched toast action disappears after its hold', (
    tester,
  ) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) {
            ctx = context;
            return const SizedBox.expand();
          },
        ),
      ),
    );
    AppToast.show(
      ctx,
      '没有找到支付宝',
      actionLabel: '保存收款码',
      onAction: () => fail('An expired action should never run'),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 5900));
    expect(find.text('保存收款码'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 101) + AppMotion.fade);
    expect(find.text('保存收款码'), findsNothing);
  });

  testWidgets('holding the toast pauses it until release', (tester) async {
    final context = await toastContext(tester);
    AppToast.show(context, '已保存到相册', actionLabel: '打开微信', onAction: () {});
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    final message = find.text('已保存到相册');
    final press = await tester.startGesture(tester.getCenter(message));
    await tester.pump(const Duration(seconds: 3));
    expect(toastOpacity(tester, message), 1);
    await press.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    expect(toastOpacity(tester, message), 1);
    await tester.pump(const Duration(milliseconds: 101) + AppMotion.fade);
    expect(message, findsNothing);
  });

  testWidgets('holding during fade restores opacity until cancel', (
    tester,
  ) async {
    final context = await toastContext(tester);
    AppToast.show(context, '已保存到相册', actionLabel: '打开微信', onAction: () {});
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 6) + AppMotion.fade ~/ 2);
    final message = find.text('已保存到相册');
    expect(toastOpacity(tester, message), closeTo(.5, .02));
    final press = await tester.startGesture(tester.getCenter(message));
    await tester.pump(const Duration(seconds: 3));
    expect(toastOpacity(tester, message), 1);
    await press.cancel();
    await tester.pump();
    await tester.pump(AppMotion.fade + const Duration(milliseconds: 1));
    expect(message, findsNothing);
  });

  testWidgets('a held toast can be replaced before release', (tester) async {
    final context = await toastContext(tester);
    AppToast.show(context, '已保存到相册', actionLabel: '打开微信', onAction: () {});
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final press = await tester.startGesture(
      tester.getCenter(find.text('已保存到相册')),
    );
    AppToast.show(context, '已发送');
    await tester.pump();
    await press.up();
    expect(find.text('已发送'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
  });

  testWidgets('toast actions use a 40dp pill inside a 44dp touch target', (
    tester,
  ) async {
    final context = await toastContext(tester);
    const ink = Color(0xFF1E1E20);
    const brand = Color(0xFF128548);
    var taps = 0;
    for (final color in [null, brand]) {
      AppToast.show(
        context,
        '已保存到相册',
        actionLabel: '打开微信',
        onAction: () => taps++,
        actionColor: color,
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final label = find.text('打开微信');
      final action = find.byType(PressScale);
      final foreground = color == null ? ink : Colors.white;
      final background = color ?? Colors.white.withValues(alpha: .96);
      final pill = find.descendant(
        of: action,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).color == background,
        ),
      );
      expect(tester.widget<Text>(label).style?.color, foreground);
      final arrow = tester.widget<Icon>(find.byIcon(AppIcons.forward));
      expect(arrow.size, 12);
      expect(arrow.color, foreground);
      expect(tester.getSize(pill).height, 40);
      expect(tester.getSize(action).height, greaterThanOrEqualTo(44));
      final toast = find
          .ancestor(of: action, matching: find.byType(DecoratedBox))
          .first;
      expect(tester.getSize(toast).height, 52);
      expect(tester.getRect(pill).top - tester.getRect(toast).top, 6);
      expect(tester.getRect(toast).right - tester.getRect(pill).right, 6);
      await tester.tapAt(tester.getRect(pill).topCenter - const Offset(0, 1));
      await tester.pumpAndSettle();
      expect(label, findsNothing);
    }
    expect(taps, 2);
  });

  testWidgets('state view shows an outline icon, message and tinted action', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        StateView(
          icon: AppIcons.warning,
          message: '加载失败',
          actionLabel: '重试',
          onAction: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final icon = tester.widget<Icon>(find.byIcon(AppIcons.warning));
    expect(icon.size, 52);
    expect(icon.color, AppTokens.light.text3);
    final action = tester.widget<AppButton>(find.byType(AppButton));
    expect(action.variant, AppButtonVariant.tinted);
    expect(find.text('加载失败'), findsOneWidget);
  });

  Widget surface(Widget child) => Directionality(
    textDirection: TextDirection.ltr,
    child: MediaQuery(
      data: const MediaQueryData(size: Size(800, 600)),
      child: Theme(data: buildAppTheme(Brightness.light), child: child),
    ),
  );

  double pulseOpacity(WidgetTester tester) => tester
      .widget<Opacity>(
        find
            .descendant(
              of: find.byType(SkeletonPulse),
              matching: find.byType(Opacity),
            )
            .first,
      )
      .opacity;

  bool placeholderVisible(WidgetTester tester) => tester
      .widget<Visibility>(
        find
            .descendant(
              of: find.byType(LoadingPlaceholder),
              matching: find.byType(Visibility),
            )
            .first,
      )
      .visible;

  testWidgets('fast loading reserves layout without painting or ticking', (
    tester,
  ) async {
    Widget loading(bool active) => surface(
      Center(
        child: LoadingPlaceholder(
          active: active,
          child: const SizedBox(
            width: 200,
            height: 100,
            child: CircularProgressIndicator(),
          ),
        ),
      ),
    );
    await tester.pumpWidget(loading(true));
    final size = tester.getSize(find.byType(LoadingPlaceholder));
    expect(placeholderVisible(tester), isFalse);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pump(const Duration(milliseconds: 299));
    expect(placeholderVisible(tester), isFalse);
    await tester.pumpWidget(loading(false));
    expect(tester.getSize(find.byType(LoadingPlaceholder)), size);
    await tester.pump(const Duration(seconds: 1));
    expect(placeholderVisible(tester), isFalse);
    expect(tester.binding.transientCallbackCount, 0);
    // A later read gets its own delay instead of inheriting the previous one.
    await tester.pumpWidget(loading(true));
    await tester.pump(const Duration(milliseconds: 299));
    expect(placeholderVisible(tester), isFalse);
    await tester.pump(const Duration(milliseconds: 1));
    expect(placeholderVisible(tester), isTrue);
    expect(tester.binding.transientCallbackCount, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('slow loading remains visible with reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      surface(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: const SkeletonList(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 299));
    expect(placeholderVisible(tester), isFalse);
    await tester.pump(const Duration(milliseconds: 1));
    expect(placeholderVisible(tester), isTrue);
    expect(pulseOpacity(tester), 1);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('shared loading indicator uses the same deferred presentation', (
    tester,
  ) async {
    await tester.pumpWidget(app(StateView.loading()));
    final paint = find.descendant(
      of: find.byType(ChhersLoader),
      matching: find.byType(CustomPaint),
    );
    expect(paint, findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pump(const Duration(milliseconds: 300));
    expect(paint, findsOneWidget);
    await tester.pumpWidget(app(const Text('已加载')));
    expect(find.byType(ChhersLoader), findsNothing);
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('skeleton waits 300ms then breathes as one group', (
    tester,
  ) async {
    await tester.pumpWidget(surface(const SkeletonList()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 299));
    expect(placeholderVisible(tester), isFalse);
    expect(pulseOpacity(tester), 1);
    await tester.pump(const Duration(milliseconds: 2));
    expect(placeholderVisible(tester), isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(pulseOpacity(tester), closeTo(.55, .01));
    expect(
      find.descendant(
        of: find.byType(SkeletonList),
        matching: find.byType(Opacity),
      ),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 800));
    expect(pulseOpacity(tester), closeTo(1, .01));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('hidden and reduced motion skeletons stop their ticker', (
    tester,
  ) async {
    Widget skeleton({required bool enabled, bool reduced = false}) => surface(
      MediaQuery(
        data: MediaQueryData(
          size: const Size(800, 600),
          disableAnimations: reduced,
        ),
        child: TickerMode(enabled: enabled, child: const SkeletonList()),
      ),
    );
    await tester.pumpWidget(skeleton(enabled: true));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(skeleton(enabled: false));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(skeleton(enabled: true, reduced: true));
    await tester.pump();
    expect(pulseOpacity(tester), 1);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('offscreen skeleton stops and resumes on returning', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      surface(
        SingleChildScrollView(
          controller: scroll,
          child: const Column(
            children: [
              SizedBox(
                height: 100,
                child: SkeletonPulse(child: SizedBox.expand()),
              ),
              SizedBox(height: 2000),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    scroll.jumpTo(900);
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    scroll.jumpTo(0);
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('arrival keeps size and mounted content, then stops ticker', (
    tester,
  ) async {
    var mounts = 0;
    Widget content(bool loading) => surface(
      Center(
        child: SkeletonContent(
          loading: loading,
          skeleton: const SizedBox(width: 200, height: 100),
          child: _ArrivalProbe(onMount: () => mounts++),
        ),
      ),
    );
    await tester.pumpWidget(content(true));
    final before = tester.getSize(find.byType(SkeletonContent));
    await tester.pumpWidget(content(false));
    expect(tester.getSize(find.byType(SkeletonContent)), before);
    expect(find.byType(SkeletonPulse), findsNothing);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(mounts, 1);
    expect(find.byType(FadeTransition), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('cached content appears without any loading ticker', (
    tester,
  ) async {
    await tester.pumpWidget(
      surface(
        const SkeletonContent(
          loading: false,
          skeleton: SizedBox(height: 100),
          child: Text('cached'),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('cached'), findsOneWidget);
    expect(find.byType(SkeletonPulse), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
  });

  test('no SnackBar remains in lib', () {
    final offenders = <String>[];
    for (final f in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (f.path.endsWith('.dart') &&
          f.readAsStringSync().contains('showSnackBar(')) {
        offenders.add(f.path);
      }
    }
    expect(offenders, isEmpty);
  });
}

class _ArrivalProbe extends StatefulWidget {
  final VoidCallback onMount;
  const _ArrivalProbe({required this.onMount});
  @override
  State<_ArrivalProbe> createState() => _ArrivalProbeState();
}

class _ArrivalProbeState extends State<_ArrivalProbe> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  Widget build(BuildContext context) => const SizedBox(width: 200, height: 100);
}
