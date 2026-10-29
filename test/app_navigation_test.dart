import 'dart:async';

import 'package:chh_app/design/theme.dart';
import 'package:chh_app/pages/home_page.dart';
import 'package:chh_app/widgets/app_shell.dart';
import 'package:chh_app/widgets/large_title_scaffold.dart';
import 'package:chh_app/ui/press.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('restores session before building pages that make requests', (
    tester,
  ) async {
    final ready = Completer<void>();
    var builds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          initialiseSession: () => ready.future,
          screenBuilders: {
            AppDestination.feed: (_) {
              builds++;
              return const Scaffold(body: Text('已恢复会话'));
            },
          },
        ),
      ),
    );
    expect(builds, 0);
    ready.complete();
    await tester.pumpAndSettle();
    expect(builds, 1);
    expect(find.text('已恢复会话'), findsOneWidget);
  });

  testWidgets('destinations are loaded lazily and preserve reading position', (
    tester,
  ) async {
    final feedScroll = ScrollController();
    final calls = <AppDestination, int>{};
    final screens = <AppDestination, WidgetBuilder>{
      for (final d in [AppDestination.feed, AppDestination.forums])
        d: (_) {
          calls[d] = (calls[d] ?? 0) + 1;
          return Scaffold(
            body: ListView(
              controller: d == AppDestination.feed ? feedScroll : null,
              children: [
                for (var i = 0; i < 40; i++)
                  SizedBox(height: 60, child: Text('${d.label}内容$i')),
              ],
            ),
          );
        },
    };
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: HomePage(screenBuilders: screens, initialiseSession: () async {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, {AppDestination.feed: 1});
    feedScroll.jumpTo(420);
    await tester.pump();
    await tester.pumpAndSettle();
    await tester.tap(find.text('版块'));
    await tester.pumpAndSettle();
    expect(calls[AppDestination.forums], 1);
    await tester.tap(find.text('精选'));
    await tester.pumpAndSettle();
    expect(feedScroll.offset, 420);
    expect(calls[AppDestination.feed], 1);
    await tester.pumpWidget(const SizedBox());
    feedScroll.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('back from a secondary tab returns to the feed once', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: HomePage(
          initialiseSession: () async {},
          screenBuilders: {
            AppDestination.feed: (_) => const Scaffold(body: Text('首页内容')),
            AppDestination.forums: (_) => const Scaffold(body: Text('版块内容')),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('版块'));
    await tester.pumpAndSettle();
    expect(find.text('版块内容'), findsOneWidget);
    final context = tester.element(find.byType(HomePage));
    expect(await Navigator.of(context).maybePop(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('首页内容'), findsOneWidget);
    expect(find.text('版块内容'), findsNothing);
    expect(await Navigator.of(context).maybePop(), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tab content moves into place without fading the whole page', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: HomePage(
          initialiseSession: () async {},
          screenBuilders: {
            AppDestination.feed: (_) => const Scaffold(body: Text('首页内容')),
            AppDestination.forums: (_) => const Scaffold(body: Text('版块内容')),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('版块'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final content = find.text('版块内容');
    final during = tester.getTopLeft(content).dy;
    expect(
      find.ancestor(of: content, matching: find.byType(Opacity)),
      findsNothing,
    );
    await tester.pumpAndSettle();
    expect(during, greaterThan(tester.getTopLeft(content).dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'home navigation uses theme typography outside the inner scaffold',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: HomePage(
            initialiseSession: () async {},
            screenBuilders: {
              AppDestination.feed: (_) => const Scaffold(body: Text('首页内容')),
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final label in ['精选', '版块', '消息', '我的']) {
        final paragraph = tester.widget<RichText>(
          find.descendant(
            of: find.text(label),
            matching: find.byType(RichText),
          ),
        );
        expect(
          paragraph.text.style?.decoration ?? TextDecoration.none,
          TextDecoration.none,
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('primary navigation fits narrow screens with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 760),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            bottomNavigationBar: AppBottomNavigation(
              current: AppDestination.messages,
              onNavigate: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('精选'), findsOneWidget);
    expect(find.text('版块'), findsOneWidget);
    expect(find.text('消息'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    final navigation = find.byType(AppBottomNavigation);
    final buttons = find.descendant(
      of: navigation,
      matching: find.byType(PressScale),
    );
    expect(buttons, findsNWidgets(4));
    for (final button in tester.widgetList<PressScale>(buttons)) {
      expect(button.onTap, isNotNull);
    }
    for (final element in buttons.evaluate()) {
      expect(
        tester.getSize(find.byWidget(element.widget)).height,
        greaterThanOrEqualTo(44),
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'shared header collapses while its inner list remains scrollable',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: LargeTitleScaffold(
            title: '版块',
            body: ListView(
              children: [
                for (var i = 0; i < 30; i++)
                  SizedBox(height: 72, child: Text('列表$i')),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -360));
      await tester.pumpAndSettle();
      expect(find.text('版块'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
