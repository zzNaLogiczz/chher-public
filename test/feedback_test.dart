import 'dart:io';

import 'package:chh_app/design/icons.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/ui/app_button.dart';
import 'package:chh_app/ui/feedback.dart';
import 'package:chh_app/widgets/state_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child) => MaterialApp(
  theme: buildAppTheme(Brightness.light),
  home: Scaffold(body: child),
);

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
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('已发送'), findsOneWidget);
    expect(tester.getTopLeft(find.text('已发送')).dy, lessThan(120));
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();
    expect(find.text('已发送'), findsNothing);
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

  testWidgets('skeleton waits 300ms then breathes as one group', (
    tester,
  ) async {
    await tester.pumpWidget(surface(const SkeletonList()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 299));
    expect(pulseOpacity(tester), 1);
    await tester.pump(const Duration(milliseconds: 2));
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
