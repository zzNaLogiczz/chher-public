import 'package:chh_app/widgets/editorial_article_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _readerKey = ValueKey('reader-page');

class _GestureObserver extends NavigatorObserver {
  int starts = 0;
  int stops = 0;
  int pops = 0;
  @override
  void didStartUserGesture(
    Route<dynamic> route,
    Route<dynamic>? previousRoute,
  ) => starts++;
  @override
  void didStopUserGesture() => stops++;
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => pops++;
}

Future<
  ({EditorialArticleRoute route, NavigatorState nav, _GestureObserver observer})
>
_open(WidgetTester tester, {bool reduceMotion = false}) async {
  final key = GlobalKey<NavigatorState>();
  final observer = _GestureObserver();
  final route = EditorialArticleRoute(
    reduceMotion: reduceMotion,
    builder: (_) => const Scaffold(
      body: SizedBox.expand(
        key: _readerKey,
        child: Align(alignment: Alignment.topLeft, child: Text('Reader')),
      ),
    ),
  );
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: key,
      navigatorObservers: [observer],
      home: const Scaffold(body: Text('Home')),
    ),
  );
  key.currentState!.push(route);
  await tester.pumpAndSettle();
  return (route: route, nav: key.currentState!, observer: observer);
}

void main() {
  testWidgets('a 200px finger movement translates the actual page by 200px', (
    tester,
  ) async {
    final fixture = await _open(tester);
    final origin = tester.getTopLeft(find.byKey(_readerKey));
    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(fixture.route.beginDismiss(), isTrue);
    fixture.route.updateDismiss(200 / screenHeight);
    await tester.pump();
    expect(
      tester.getTopLeft(find.byKey(_readerKey)).dy - origin.dy,
      closeTo(200, .01),
    );
    // Returning 75px is equally direct and does not start a Hero back flight.
    fixture.route.updateDismiss(-75 / screenHeight);
    await tester.pump();
    expect(
      tester.getTopLeft(find.byKey(_readerKey)).dy - origin.dy,
      closeTo(125, .01),
    );
    expect(fixture.nav.userGestureInProgress, isFalse);
    expect(fixture.observer.starts, 0);
    fixture.route.endDismiss(-1);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byKey(_readerKey)).dy,
      closeTo(origin.dy, .01),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a short drag cancels without detaching content from the page', (
    tester,
  ) async {
    final fixture = await _open(tester);
    final origin = tester.getTopLeft(find.byKey(_readerKey));
    fixture.route.beginDismiss();
    fixture.route.updateDismiss(.1);
    await tester.pump();
    expect(
      tester.getTopLeft(find.byKey(_readerKey)).dy,
      greaterThan(origin.dy),
    );
    fixture.route.endDismiss(.2);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byKey(_readerKey)).dy,
      closeTo(origin.dy, .01),
    );
    expect(find.text('Reader'), findsOneWidget);
    expect(fixture.observer.pops, 0);
    expect(fixture.observer.starts, 0);
    expect(fixture.observer.stops, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a committed drag uses an ordinary pop and returns to existing home',
    (tester) async {
      final fixture = await _open(tester);
      fixture.route.beginDismiss();
      fixture.route.updateDismiss(.3);
      fixture.route.endDismiss(1.2);
      await tester.pumpAndSettle();
      expect(find.text('Reader'), findsNothing);
      expect(find.text('Home'), findsOneWidget);
      expect(fixture.observer.pops, 1);
      expect(fixture.observer.starts, 0);
      expect(fixture.nav.userGestureInProgress, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an ongoing cancel spring can be grabbed at its current displayed position',
    (tester) async {
      final fixture = await _open(tester);
      final height =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      fixture.route.beginDismiss();
      fixture.route.updateDismiss(.16);
      fixture.route.endDismiss(0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));
      final current = tester.getTopLeft(find.byKey(_readerKey)).dy;
      expect(fixture.route.beginDismiss(), isTrue);
      await tester.pump();
      expect(
        tester.getTopLeft(find.byKey(_readerKey)).dy,
        closeTo(current, .01),
      );
      fixture.route.updateDismiss(.05);
      await tester.pump();
      expect(
        tester.getTopLeft(find.byKey(_readerKey)).dy,
        closeTo(current + height * .05, .01),
      );
      fixture.route.endDismiss(-1);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(_readerKey)).dy, closeTo(0, .01));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('system pop while held does not resume a cancellation ticker', (
    tester,
  ) async {
    final fixture = await _open(tester);
    fixture.route.beginDismiss();
    fixture.route.updateDismiss(.05);
    fixture.nav.pop();
    fixture.route.endDismiss(0);
    await tester.pumpAndSettle();
    expect(find.text('Reader'), findsNothing);
    expect(fixture.nav.userGestureInProgress, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'removing the route during cancel disposes its independent ticker',
    (tester) async {
      final fixture = await _open(tester);
      fixture.route.beginDismiss();
      fixture.route.updateDismiss(.1);
      fixture.route.endDismiss(0);
      await tester.pump(const Duration(milliseconds: 16));
      fixture.nav.removeRoute(fixture.route);
      await tester.pumpAndSettle();
      expect(find.text('Reader'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reduced motion keeps direct manipulation and restores cancelled position',
    (tester) async {
      final fixture = await _open(tester, reduceMotion: true);
      final height =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      fixture.route.beginDismiss();
      fixture.route.updateDismiss(.1);
      await tester.pump();
      expect(
        tester.getTopLeft(find.byKey(_readerKey)).dy,
        closeTo(height * .1, .01),
      );
      fixture.route.endDismiss(0);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(_readerKey)).dy, closeTo(0, .01));
      fixture.nav.pop();
      await tester.pumpAndSettle();
      expect(find.text('Reader'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Hero starts closing at the released global rectangle, not the original origin',
    (tester) async {
      const fromKey = ValueKey('home-cover');
      const toKey = ValueKey('reader-cover');
      const flightKey = ValueKey('flying-cover');
      late EditorialArticleRoute route;
      Widget hero(Key key, double width, double height) => Hero(
        tag: 'direct-cover',
        createRectTween: (begin, end) => RectTween(begin: begin, end: end),
        flightShuttleBuilder: (_, _, _, _, _) =>
            const ColoredBox(key: flightKey, color: Color(0xff111113)),
        child: SizedBox(
          key: key,
          width: width,
          height: height,
          child: const ColoredBox(color: Color(0xff111113)),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: GestureDetector(
                  onTap: () {
                    route = EditorialArticleRoute(
                      builder: (_) => Scaffold(
                        body: Align(
                          alignment: Alignment.topLeft,
                          child: hero(toKey, 300, 250),
                        ),
                      ),
                    );
                    Navigator.of(context).push(route);
                  },
                  child: hero(fromKey, 150, 100),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(fromKey));
      await tester.pumpAndSettle();
      route.beginDismiss();
      route.updateDismiss(.3);
      await tester.pump();
      expect(find.byKey(flightKey), findsNothing);
      final released = tester.getRect(find.byKey(toKey));
      route.endDismiss(1);
      await tester.pump();
      await tester.pump();
      final flight = tester.getRect(find.byKey(flightKey));
      expect(flight.top, closeTo(released.top, 1));
      expect(flight.left, closeTo(released.left, 1));
      expect(flight.width, closeTo(released.width, 1));
      expect(flight.height, closeTo(released.height, 1));
      await tester.pumpAndSettle();
      expect(find.byKey(fromKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
