import 'package:chh_app/design/loading_tokens.dart';
import 'package:chh_app/design/motion.dart';
import 'package:chh_app/widgets/chhers_loader.dart';
import 'package:chh_app/widgets/chhers_loading_transition.dart';
import 'package:chh_app/widgets/expressive_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _surface(Widget child, {bool reduced = false, bool enabled = true}) =>
    MaterialApp(
      home: TickerMode(
        enabled: enabled,
        child: MediaQuery(
          data: MediaQueryData(
            size: const Size(800, 600),
            disableAnimations: reduced,
          ),
          child: Scaffold(body: Center(child: child)),
        ),
      ),
    );

Finder _paint(Type type) =>
    find.descendant(of: find.byType(type), matching: find.byType(CustomPaint));

Iterable<FadeTransition> _loaderFades(WidgetTester tester) =>
    tester.widgetList<FadeTransition>(
      find.descendant(
        of: find.byType(ChhersLoader),
        matching: find.byType(FadeTransition),
      ),
    );

void main() {
  testWidgets('fast arrival skips painting and leaves no waiting ticker', (
    tester,
  ) async {
    await tester.pumpWidget(
      _surface(const ChhersLoadingTransition(child: null)),
    );
    await tester.pump(const Duration(milliseconds: 299));
    expect(_paint(ChhersLoader), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);

    await tester.pumpWidget(
      _surface(const ChhersLoadingTransition(child: Text('已加载'))),
    );
    expect(find.text('已加载'), findsOneWidget);
    expect(find.byType(ChhersLoader), findsNothing);
    await tester.pump(AppMotion.loadingDelay);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('slow arrival fades the wordmark out before revealing content', (
    tester,
  ) async {
    await tester.pumpWidget(
      _surface(const ChhersLoadingTransition(child: null)),
    );
    await tester.pump(const Duration(milliseconds: 299));
    expect(_paint(ChhersLoader), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    expect(_paint(ChhersLoader), findsOneWidget);
    expect(_loaderFades(tester).first.opacity.value, 0);
    await tester.pump(AppMotion.loadingIn ~/ 2);
    expect(_loaderFades(tester).first.opacity.value, closeTo(.5, .01));
    await tester.pump(AppMotion.loadingIn ~/ 2);
    expect(_loaderFades(tester).first.opacity.value, 1);

    await tester.pumpWidget(
      _surface(const ChhersLoadingTransition(child: Text('已加载'))),
    );
    expect(find.text('已加载'), findsNothing);
    await tester.pump();
    await tester.pump(AppMotion.loadingOut ~/ 2);
    expect(_paint(ChhersLoader), findsOneWidget);
    await tester.pump(
      AppMotion.loadingOut ~/ 2 + const Duration(milliseconds: 1),
    );
    expect(find.byType(ChhersLoader), findsNothing);
    expect(find.text('已加载'), findsOneWidget);
    expect(find.byType(ExpressivePageReveal), findsOneWidget);
    await tester.pump();
    await tester.pump(AppMotion.fade + const Duration(milliseconds: 1));
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('reduced motion fades to a static mark and static C', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _surface(
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [ChhersLoader(), ChhersSpinner()],
        ),
        reduced: true,
      ),
    );
    await tester.pump(AppMotion.loadingDelay);
    await tester.pump(AppMotion.loadingIn + const Duration(milliseconds: 1));
    expect(_paint(ChhersLoader), findsOneWidget);
    expect(_paint(ChhersSpinner), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ChhersSpinner),
        matching: find.byType(RotationTransition),
      ),
      findsNothing,
    );
    expect(_loaderFades(tester).single.opacity.value, .75);
    expect(find.bySemanticsLabel('正在加载'), findsNWidgets(2));
    semantics.dispose();
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets(
    'loops stop offscreen, when muted, in background and on dispose',
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      Widget view({bool enabled = true}) => _surface(
        SingleChildScrollView(
          controller: scroll,
          child: const Column(
            children: [ChhersLoader(), ChhersSpinner(), SizedBox(height: 1000)],
          ),
        ),
        enabled: enabled,
      );

      await tester.pumpWidget(view());
      await tester.pump(AppMotion.loadingDelay);
      await tester.pump(AppMotion.loadingIn + const Duration(milliseconds: 1));
      expect(tester.binding.transientCallbackCount, 2);

      scroll.jumpTo(350);
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);

      scroll.jumpTo(0);
      await tester.pump();
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 2);

      await tester.pumpWidget(view(enabled: false));
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(view());
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 2);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 2);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets('pull paints a prefix with the requested fraction of ink', (
    tester,
  ) async {
    Future<List<Path>> draw(double progress, {bool reduced = false}) async {
      await tester.pumpWidget(
        _surface(ChhersLoader.progress(progress: progress), reduced: reduced),
      );
      final widget = tester.widget<CustomPaint>(_paint(ChhersLoader));
      final canvas = TestRecordingCanvas();
      widget.painter!.paint(canvas, tester.getSize(_paint(ChhersLoader)));
      return [
        for (final call in canvas.invocations)
          if (call.invocation.memberName == #drawPath)
            call.invocation.positionalArguments.first as Path,
      ];
    }

    double length(List<Path> paths) => paths
        .expand((path) => path.computeMetrics())
        .fold(0, (sum, metric) => sum + metric.length);
    final full = await draw(1);
    expect(full, hasLength(10));
    expect(LoadingTokens.viewWidth, 147.43);
    final nominal = ChhersLoaderSize.refresh.viewSize;
    expect(tester.getSize(_paint(ChhersLoader)), nominal);

    // R2b endpoints and lengths in writing order, before the painter scales.
    const reference = [
      (Offset(23.05, -3.05), Offset(23.05, 16.05), 63.61),
      (Offset(32.25, -7), Offset(32.25, 20), 27.0),
      (Offset(32.25, 7.2), Offset(46.65, 20), 35.42),
      (Offset(57.65, -7), Offset(57.65, 20), 27.0),
      (Offset(57.65, 7.2), Offset(72.05, 20), 35.42),
      (Offset(81.85, 10), Offset(101.85, 10), 20.0),
      (Offset(101.85, 10), Offset(99.51, 16.43), 55.85),
      (Offset(110.05, 0), Offset(110.05, 20), 20.0),
      (Offset(110.05, 8.28), Offset(120.43, 0), 15.11),
      (Offset(139.93, 2.2), Offset(128.43, 17.2), 48.97),
    ];
    // Flutter approximates curved contour lengths when building PathMetrics.
    expect(length(full), closeTo(348.37, 2));
    for (final (index, (start, end, expectedLength)) in reference.indexed) {
      final stroke = full[index].computeMetrics().single;
      expect(stroke.length, closeTo(expectedLength, .8), reason: '笔画 $index');
      expect(
        (stroke.getTangentForOffset(0)!.position - start).distance,
        lessThan(.001),
      );
      expect(
        (stroke.getTangentForOffset(stroke.length)!.position - end).distance,
        lessThan(.001),
      );
    }
    final s = full.last.computeMetrics().single;
    for (final (fraction, point) in const [
      (.10, Offset(135.72, .04)),
      (.25, Offset(129.26, 2.68)),
      (.40, Offset(131.29, 8.77)),
      (.55, Offset(138.33, 10.84)),
      (.70, Offset(141.07, 16.71)),
      (.85, Offset(134.94, 20)),
      (.95, Offset(130.26, 18.81)),
    ]) {
      expect(
        (s.getTangentForOffset(s.length * fraction)!.position - point).distance,
        lessThan(.35),
      );
    }
    for (final fraction in [.1, .4, .7]) {
      final prefix = await draw(fraction);
      expect(length(prefix) / length(full), closeTo(fraction, .002));
      expect(
        prefix.first.getBounds().left,
        greaterThanOrEqualTo(full.first.getBounds().left),
      );
    }

    expect(await draw(0), isEmpty);
    expect(await draw(.1, reduced: true), hasLength(10));
    expect(tester.binding.transientCallbackCount, 0);
  });
}
