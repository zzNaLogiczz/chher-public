import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/core/appearance.dart';
import 'package:chh_app/data/image_disk_cache.dart';
import 'package:chh_app/pages/settings_page.dart';
import 'package:chh_app/ui/sheet_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shared_sheet_back_test.dart' show mountRoute, predictive;

void main() {
  for (final style in AppearanceStyle.values) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'named settings follows platform progress $style $brightness',
        (tester) async {
          final previousCache = imageDiskCache;
          imageDiskCache = ImageDiskCache(null);
          final appearance = AppearanceController(directory: () async => null);
          appearance.setStyle(style);
          appearance.set(
            brightness == Brightness.dark
                ? AppearanceMode.dark
                : AppearanceMode.light,
          );
          addTearDown(() {
            imageDiskCache = previousCache;
            appearance.dispose();
          });
          final nav = GlobalKey<NavigatorState>();
          await tester.pumpWidget(
            MaterialApp(
              navigatorKey: nav,
              theme: buildAppTheme(brightness, style),
              home: const Scaffold(body: Text('root')),
              routes: {
                '/settings': (_) =>
                    SettingsPage(appearanceController: appearance),
              },
            ),
          );
          nav.currentState!.pushNamed('/settings');
          await tester.pumpAndSettle();
          await predictive(tester, 'startBackGesture');
          for (final progress in [.1, .2, .4, .5]) {
            await predictive(tester, 'updateBackGestureProgress', progress);
            await tester.pump(const Duration(milliseconds: 300));
            expect(
              tester.getTopLeft(find.byType(Scaffold).last).dx,
              closeTo(800 * progress, .1),
            );
            expect(
              tester.getTopLeft(find.byType(Scaffold).first).dx,
              closeTo(-800 / 3 * (1 - progress), .1),
            );
            expect(tester.binding.transientCallbackCount, 0);
          }
          await predictive(tester, 'cancelBackGesture');
          await tester.pumpAndSettle();
          expect(find.byType(SettingsPage), findsOneWidget);
          expect(tester.getTopLeft(find.byType(Scaffold).last).dx, 0);
          await predictive(tester, 'startBackGesture');
          await predictive(tester, 'updateBackGestureProgress', .5);
          await tester.pump();
          await predictive(tester, 'commitBackGesture');
          await tester.pump();
          expect(
            tester.getTopLeft(find.byType(Scaffold).last).dx,
            closeTo(400, .1),
          );
          await tester.pumpAndSettle();
          expect(find.byType(SettingsPage), findsNothing);
          expect(nav.currentState!.userGestureInProgress, isFalse);
          expect(tester.binding.transientCallbackCount, 0);
        },
      );
    }
  }

  for (final touch in [
    null,
    <double>[0, 0],
  ]) {
    for (final commit in [false, true]) {
      testWidgets(
        'ambiguous start retains progress touch=$touch commit=$commit',
        (tester) async {
          final nav = await mountRoute(tester);
          await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
            'flutter/backgesture',
            const StandardMethodCodec().encodeMethodCall(
              MethodCall('startBackGesture', {
                'touchOffset': touch,
                'progress': 0.0,
                'swipeEdge': 0,
              }),
            ),
            (_) {},
          );
          // A zero-coordinate start alone must not move a button-triggered route.
          await tester.pump();
          expect(tester.getTopLeft(find.byType(Scaffold).last).dx, 0);
          expect(nav.currentState!.userGestureInProgress, isFalse);
          for (final progress in [.1, .25, .5, .35]) {
            await predictive(tester, 'updateBackGestureProgress', progress);
            await tester.pump(const Duration(milliseconds: 300));
            expect(
              tester.getTopLeft(find.byType(Scaffold).last).dx,
              closeTo(800 * progress, .1),
            );
            expect(
              tester.getTopLeft(find.byType(Scaffold).first).dx,
              closeTo(-800 / 3 * (1 - progress), .1),
            );
            expect(tester.binding.transientCallbackCount, 0);
          }
          final released = tester.getTopLeft(find.byType(Scaffold).last).dx;
          await predictive(
            tester,
            commit ? 'commitBackGesture' : 'cancelBackGesture',
          );
          await tester.pump();
          expect(
            tester.getTopLeft(find.byType(Scaffold).last).dx,
            closeTo(released, .1),
          );
          await tester.pumpAndSettle();
          expect(find.text('detail'), commit ? findsNothing : findsOneWidget);
          expect(nav.currentState!.userGestureInProgress, isFalse);
          expect(tester.binding.transientCallbackCount, 0);
        },
      );
    }
  }

  testWidgets('invoke without start pops once with an ordinary transition', (
    tester,
  ) async {
    final nav = await mountRoute(tester);
    await predictive(tester, 'commitBackGesture');
    await tester.pump();
    expect(find.text('detail'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.getTopLeft(find.byType(Scaffold).last).dx, greaterThan(0));
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsNothing);
    expect(find.text('root'), findsOneWidget);
    expect(nav.currentState!.userGestureInProgress, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('cancel followed by invoke without start still pops', (
    tester,
  ) async {
    final nav = await mountRoute(tester);
    await predictive(tester, 'startBackGesture');
    await predictive(tester, 'updateBackGestureProgress', .3);
    await predictive(tester, 'cancelBackGesture');
    await tester.pumpAndSettle();
    await predictive(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsNothing);
    expect(nav.currentState!.userGestureInProgress, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('start progress commit tracks both routes linearly', (
    tester,
  ) async {
    final nav = await mountRoute(tester);
    final event = PredictiveBackEvent.fromMap({
      'touchOffset': <double>[200, 200],
      'progress': .25,
      'swipeEdge': 0,
    });
    await predictive(tester, 'startBackGesture');
    await predictive(tester, 'updateBackGestureProgress', event.progress);
    await tester.pump();
    expect(tester.getTopLeft(find.byType(Scaffold).last).dx, closeTo(200, .1));
    expect(
      tester.getTopLeft(find.byType(Scaffold).first).dx,
      closeTo(-200, .1),
    );
    await predictive(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsNothing);
    expect(nav.currentState!.userGestureInProgress, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('start cancel restores the route and balances user gesture', (
    tester,
  ) async {
    final nav = await mountRoute(tester);
    await predictive(tester, 'startBackGesture');
    await predictive(tester, 'cancelBackGesture');
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsOneWidget);
    expect(tester.getTopLeft(find.byType(Scaffold).last).dx, 0);
    expect(nav.currentState!.userGestureInProgress, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
  });

  for (final reduced in [false, true]) {
    testWidgets('invoke honors PopScope reduced=$reduced', (tester) async {
      var blocked = 0;
      await mountRoute(
        tester,
        canPop: false,
        reduced: reduced,
        onBlocked: () => blocked++,
      );
      await predictive(tester, 'commitBackGesture');
      await tester.pumpAndSettle();
      expect(find.text('detail'), findsOneWidget);
      expect(blocked, 1);
    });
  }

  testWidgets('invoke after cancellation dismisses panel before its host', (
    tester,
  ) async {
    final nav = await mountRoute(tester);
    await predictive(tester, 'startBackGesture');
    await predictive(tester, 'updateBackGestureProgress', .3);
    await predictive(tester, 'cancelBackGesture');
    await tester.pumpAndSettle();
    showAppSheet<void>(
      tester.element(find.text('detail')),
      builder: (_) => const SizedBox(height: 100, child: Text('panel')),
    );
    await tester.pumpAndSettle();
    await predictive(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(find.text('panel'), findsNothing);
    expect(find.text('detail'), findsOneWidget);
    expect(nav.currentState!.userGestureInProgress, isFalse);
  });

  testWidgets('commit interrupts cancellation without leaving a live gesture', (
    tester,
  ) async {
    final nav = await mountRoute(tester);
    await predictive(tester, 'startBackGesture');
    await predictive(tester, 'updateBackGestureProgress', .4);
    await predictive(tester, 'cancelBackGesture');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    final before = tester.getTopLeft(find.byType(Scaffold).last).dx;
    await predictive(tester, 'commitBackGesture');
    await tester.pump();
    expect(
      tester.getTopLeft(find.byType(Scaffold).last).dx,
      closeTo(before, .1),
    );
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsNothing);
    expect(nav.currentState!.userGestureInProgress, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
  });

  for (final panel in [false, true]) {
    testWidgets(
      'intercepted invoke keeps cancelled page settling panel=$panel',
      (tester) async {
        final nav = await mountRoute(tester);
        final locked = ValueNotifier(false);
        addTearDown(locked.dispose);
        var blocked = 0;
        nav.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => ValueListenableBuilder<bool>(
              valueListenable: locked,
              builder: (_, locked, _) => PopScope(
                canPop: !locked,
                onPopInvokedWithResult: (didPop, _) {
                  if (!didPop) blocked++;
                },
                child: const Scaffold(body: Text('editor')),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await predictive(tester, 'startBackGesture');
        await predictive(tester, 'updateBackGestureProgress', .4);
        await predictive(tester, 'cancelBackGesture');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 30));
        if (panel) {
          showAppSheet<void>(
            tester.element(find.text('editor')),
            builder: (_) => const SizedBox(height: 100, child: Text('panel')),
          );
        } else {
          locked.value = true;
        }
        await tester.pump();
        await predictive(tester, 'commitBackGesture');
        await tester.pumpAndSettle();
        expect(find.text('editor'), findsOneWidget);
        expect(find.text('panel'), findsNothing);
        expect(
          tester
              .getTopLeft(
                find.ancestor(
                  of: find.text('editor'),
                  matching: find.byType(Scaffold),
                ),
              )
              .dx,
          0,
        );
        expect(blocked, panel ? 0 : 1);
        expect(nav.currentState!.userGestureInProgress, isFalse);
        expect(tester.binding.transientCallbackCount, 0);
      },
    );
  }

  testWidgets('a draft lock added during progress receives the commit veto', (
    tester,
  ) async {
    final nav = await mountRoute(tester);
    final locked = ValueNotifier(false);
    addTearDown(locked.dispose);
    var confirmations = 0;
    nav.currentState!.push(
      MaterialPageRoute<void>(
        builder: (context) => ValueListenableBuilder<bool>(
          valueListenable: locked,
          builder: (context, locked, _) => PopScope(
            canPop: !locked,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) {
                confirmations++;
                showDialog<void>(
                  context: context,
                  builder: (_) => const AlertDialog(content: Text('保留草稿')),
                );
              }
            },
            child: const Scaffold(body: Text('editor')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await predictive(tester, 'startBackGesture');
    await predictive(tester, 'updateBackGestureProgress', .4);
    locked.value = true;
    await tester.pump();
    await predictive(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(find.text('editor'), findsOneWidget);
    expect(find.text('保留草稿'), findsOneWidget);
    expect(confirmations, 1);
    expect(nav.currentState!.userGestureInProgress, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
  });

  for (final buttonEvent in [false, true]) {
    testWidgets(
      'ordinary physical or three-button back works buttonEvent=$buttonEvent',
      (tester) async {
        final nav = await mountRoute(tester);
        if (buttonEvent) {
          await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
            'flutter/backgesture',
            const StandardMethodCodec().encodeMethodCall(
              const MethodCall('startBackGesture', {
                'touchOffset': null,
                'progress': 0.0,
                'swipeEdge': 0,
              }),
            ),
            (_) {},
          );
          await predictive(tester, 'commitBackGesture');
        } else {
          await tester.binding.handlePopRoute();
        }
        await tester.pumpAndSettle();
        expect(find.text('detail'), findsNothing);
        expect(nav.currentState!.userGestureInProgress, isFalse);
      },
    );
  }

  testWidgets(
    'framework handles back only while a route or PopScope needs it',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.detached,
        ),
      );
      final handlesBack = <bool>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemNavigator.setFrameworkHandlesBack') {
            handlesBack.add(call.arguments as bool);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final nav = await mountRoute(tester);
      expect(handlesBack, contains(false));
      expect(handlesBack.last, isTrue);
      await predictive(tester, 'commitBackGesture');
      await tester.pumpAndSettle();
      expect(nav.currentState!.canPop(), isFalse);
      expect(handlesBack.last, isFalse);
    },
  );

  testWidgets('root invoke is handed back to the platform', (tester) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: const Scaffold(body: Text('root')),
      ),
    );
    await tester.pumpAndSettle();
    await predictive(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(find.text('root'), findsOneWidget);
    expect(
      calls.where((call) => call.method == 'SystemNavigator.pop'),
      hasLength(1),
    );
  });
}
