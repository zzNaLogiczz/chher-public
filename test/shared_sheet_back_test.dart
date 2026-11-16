import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/motion.dart';
import 'package:flutter/physics.dart';
import 'package:chh_app/ui/sheet_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<GlobalKey<NavigatorState>> mountRoute(
  WidgetTester tester, {
  bool canPop = true,
  bool reduced = false,
  VoidCallback? onBlocked,
}) async {
  final key = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: key,
      theme: buildAppTheme(
        Brightness.light,
      ).copyWith(platform: TargetPlatform.android),
      builder: (_, child) => MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: child!,
      ),
      home: const Scaffold(body: Text('root')),
    ),
  );
  key.currentState!.push(
    MaterialPageRoute<void>(
      builder: (_) => PopScope(
        canPop: canPop,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) onBlocked?.call();
        },
        child: const Scaffold(body: Text('detail')),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return key;
}

Future<void> predictive(
  WidgetTester tester,
  String method, [
  double progress = 0,
]) => tester.binding.defaultBinaryMessenger.handlePlatformMessage(
  'flutter/backgesture',
  const StandardMethodCodec().encodeMethodCall(
    MethodCall(method, {
      'touchOffset': <double>[0.0, 200.0],
      'progress': progress,
      'swipeEdge': 0,
    }),
  ),
  (_) {},
);

Future<void> mountSheet(
  WidgetTester tester, {
  bool canPop = true,
  VoidCallback? onBlocked,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showAppSheet<void>(
              context,
              builder: (_) => PopScope(
                canPop: canPop,
                onPopInvokedWithResult: (didPop, _) {
                  if (!didPop) onBlocked?.call();
                },
                child: const SizedBox(
                  height: 400,
                  child: SheetScaffold(title: 'panel', body: SizedBox.expand()),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('ordinary push uses reveal and keeps velocity when reversed', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: buildAppTheme(Brightness.light),
        home: const Scaffold(body: Text('root')),
      ),
    );
    final route = MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('detail')),
    );
    navigator.currentState!.push(route);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final simulation = SpringSimulation(AppMotion.reveal.description, 0, 1, 0);
    expect(route.animation!.value, closeTo(simulation.x(.05), .001));
    final before = route.animation!.value;
    navigator.currentState!.pop();
    await tester.pump();
    expect(route.animation!.value, closeTo(before, .001));
    await tester.pump(const Duration(milliseconds: 5));
    expect(route.animation!.value, greaterThan(before));
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets(
    'predictive back tracks, cancels and commits without a lingering ticker',
    (tester) async {
      final key = await mountRoute(tester);
      await predictive(tester, 'startBackGesture');
      await predictive(tester, 'updateBackGestureProgress', .35);
      await tester.pump();
      expect(tester.getTopLeft(find.byType(Scaffold).last).dx, closeTo(280, 1));
      await predictive(tester, 'cancelBackGesture');
      await tester.pumpAndSettle();
      expect(find.text('detail'), findsOneWidget);
      expect(tester.getTopLeft(find.byType(Scaffold).last).dx, 0);
      expect(key.currentState!.userGestureInProgress, false);
      await predictive(tester, 'startBackGesture');
      await predictive(tester, 'updateBackGestureProgress', .6);
      await predictive(tester, 'commitBackGesture');
      await tester.pumpAndSettle();
      expect(find.text('detail'), findsNothing);
      expect(key.currentState!.userGestureInProgress, false);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets('a cancelled back spring can be grabbed again', (tester) async {
    final key = await mountRoute(tester);
    await predictive(tester, 'startBackGesture');
    await predictive(tester, 'updateBackGestureProgress', .4);
    await predictive(tester, 'cancelBackGesture');
    await tester.pump(const Duration(milliseconds: 40));
    final before = tester.getTopLeft(find.byType(Scaffold).last).dx;
    await predictive(tester, 'startBackGesture');
    await tester.pump();
    expect(
      tester.getTopLeft(find.byType(Scaffold).last).dx,
      closeTo(before, 1),
    );
    await predictive(tester, 'updateBackGestureProgress', .2);
    await tester.pump();
    expect(
      tester.getTopLeft(find.byType(Scaffold).last).dx,
      closeTo(before + 160, 1),
    );
    await predictive(tester, 'cancelBackGesture');
    await tester.pumpAndSettle();
    expect(key.currentState!.userGestureInProgress, false);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('edge drag cancels then dismisses using the same transition', (
    tester,
  ) async {
    await mountRoute(tester);
    await tester.dragFrom(const Offset(1, 250), const Offset(160, 0));
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsOneWidget);
    await tester.dragFrom(const Offset(1, 250), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsNothing);
  });

  testWidgets('PopScope blocks predictive gesture and physical back', (
    tester,
  ) async {
    var blocked = 0;
    await mountRoute(tester, canPop: false, onBlocked: () => blocked++);
    await predictive(tester, 'startBackGesture');
    await predictive(tester, 'updateBackGestureProgress', .5);
    await tester.pump();
    expect(tester.getTopLeft(find.byType(Scaffold).last).dx, 0);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsOneWidget);
    expect(blocked, 1);
  });

  testWidgets('reduced motion does not track predictive or edge displacement', (
    tester,
  ) async {
    await mountRoute(tester, reduced: true);
    await predictive(tester, 'startBackGesture');
    await predictive(tester, 'updateBackGestureProgress', .4);
    await tester.pump();
    expect(tester.getTopLeft(find.byType(Scaffold).last).dx, 0);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsNothing);
  });

  testWidgets('sheet has 8 inset, follows drag and dims scrim by position', (
    tester,
  ) async {
    await mountSheet(tester);
    final panel = find.byType(AppSheetSurface);
    final before = tester.getRect(panel);
    expect(before.left, 8);
    expect(before.right, 792);
    expect(before.bottom, 592);
    final route = ModalRoute.of(tester.element(panel))! as AppSheetRoute;
    final visibility = route.sheetVisibility.value;
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('panel')),
    );
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    final atStart = tester.getRect(panel).top;
    await gesture.moveBy(const Offset(0, 60));
    await tester.pump();
    expect(tester.getRect(panel).top - atStart, closeTo(60, .1));
    expect(route.sheetVisibility.value, lessThan(visibility));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getRect(panel).top, closeTo(before.top, .1));
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('sheet closes past 40 percent even with a slow release', (
    tester,
  ) async {
    await mountSheet(tester);
    await tester.timedDrag(
      find.text('panel'),
      const Offset(0, 210),
      const Duration(seconds: 2),
    );
    await tester.pumpAndSettle();
    expect(find.text('panel'), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('cancelling a long sheet drag restores it instead of closing', (
    tester,
  ) async {
    await mountSheet(tester);
    final panel = find.byType(AppSheetSurface);
    final before = tester.getRect(panel);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('panel')),
    );
    await gesture.moveBy(const Offset(0, 30));
    await gesture.moveBy(const Offset(0, 210));
    await tester.pump();
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(tester.getRect(panel), before);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('sheet fast release closes below distance threshold', (
    tester,
  ) async {
    await mountSheet(tester);
    await tester.fling(find.text('panel'), const Offset(0, 110), 1100);
    await tester.pumpAndSettle();
    expect(find.text('panel'), findsNothing);
  });

  testWidgets('a PopScope veto during close restores the panel', (
    tester,
  ) async {
    final canPop = ValueNotifier(true);
    addTearDown(canPop.dispose);
    var blocked = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showAppSheet<void>(
                context,
                builder: (_) => ValueListenableBuilder<bool>(
                  valueListenable: canPop,
                  builder: (_, allowed, child) => PopScope(
                    canPop: allowed,
                    onPopInvokedWithResult: (didPop, _) {
                      if (!didPop) blocked++;
                    },
                    child: child!,
                  ),
                  child: const SizedBox(
                    height: 400,
                    child: SheetScaffold(
                      title: 'panel',
                      body: SizedBox.expand(),
                    ),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final panel = find.byType(AppSheetSurface);
    final before = tester.getRect(panel);
    await tester.timedDrag(
      find.text('panel'),
      const Offset(0, 210),
      const Duration(seconds: 2),
    );
    await tester.pump(const Duration(milliseconds: 16));
    canPop.value = false;
    await tester.pumpAndSettle();
    expect(find.text('panel'), findsOneWidget);
    expect(tester.getRect(panel), before);
    expect(blocked, 1);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('sheet respects PopScope on drag and retains contents', (
    tester,
  ) async {
    var blocked = 0;
    await mountSheet(tester, canPop: false, onBlocked: () => blocked++);
    final before = tester.getRect(find.byType(AppSheetSurface));
    await tester.timedDrag(
      find.text('panel'),
      const Offset(0, 210),
      const Duration(seconds: 2),
    );
    await tester.pumpAndSettle();
    expect(find.text('panel'), findsOneWidget);
    expect(tester.getRect(find.byType(AppSheetSurface)), before);
    expect(blocked, 1);
  });
}
