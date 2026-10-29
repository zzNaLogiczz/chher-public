import 'dart:io';

import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/ui/nav_bar.dart';
import 'package:chh_app/widgets/app_shell.dart';
import 'package:chh_app/widgets/large_title_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget home) =>
    MaterialApp(theme: buildAppTheme(Brightness.light), home: home);

Widget rows() => ListView.builder(
  itemCount: 100,
  itemBuilder: (_, i) => SizedBox(height: 60, child: Text('row$i')),
);

double opacityOf(WidgetTester tester, Key key) =>
    tester.widget<Opacity>(find.byKey(key)).opacity;

void main() {
  testWidgets(
    'root destinations never show back even when the navigator can pop',
    (tester) async {
      await tester.pumpWidget(app(const SizedBox()));
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .push(
            MaterialPageRoute<void>(
              builder: (_) => const AppShell(
                title: '消息',
                current: AppDestination.messages,
                body: SizedBox(),
              ),
            ),
          );
      await tester.pumpAndSettle();
      expect(find.byTooltip('返回'), findsNothing);
    },
  );

  testWidgets('pushed pages show back by default', (tester) async {
    await tester.pumpWidget(app(LargeTitleScaffold(title: '设置', body: rows())));
    expect(find.byTooltip('返回'), findsOneWidget);
  });

  testWidgets('grouped surface paints the grouped background', (tester) async {
    await tester.pumpWidget(
      app(
        LargeTitleScaffold(
          title: '我的',
          showBack: false,
          surface: AppSurface.grouped,
          body: rows(),
        ),
      ),
    );
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      AppTokens.light.grouped,
    );
  });

  testWidgets('edge fade is clear at rest and opaque after 12dp', (
    tester,
  ) async {
    await tester.pumpWidget(app(LargeTitleScaffold(title: '设置', body: rows())));
    expect(opacityOf(tester, NavOverlay.edgeKey), 0);

    final outer = tester
        .state<NestedScrollViewState>(find.byType(NestedScrollView))
        .outerController;
    outer.jumpTo(6);
    await tester.pump();
    expect(opacityOf(tester, NavOverlay.edgeKey), closeTo(0.5, 0.01));

    outer.jumpTo(30);
    await tester.pump();
    expect(opacityOf(tester, NavOverlay.edgeKey), 1);
  });

  testWidgets('inline title appears once the large title scrolls away', (
    tester,
  ) async {
    await tester.pumpWidget(app(LargeTitleScaffold(title: '设置', body: rows())));
    expect(opacityOf(tester, NavOverlay.inlineTitleKey), 0);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('row3')),
    );
    await gesture.moveBy(const Offset(0, -20));
    await gesture.moveBy(const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(opacityOf(tester, NavOverlay.inlineTitleKey), 1);

    await gesture.moveBy(const Offset(0, 220));
    await tester.pumpAndSettle();
    expect(opacityOf(tester, NavOverlay.inlineTitleKey), 0);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('title accessory sits on the large title row', (tester) async {
    await tester.pumpWidget(
      app(
        LargeTitleScaffold(
          title: '精选',
          showBack: false,
          titleAccessory: const SizedBox(
            key: ValueKey('accessory'),
            width: 44,
            height: 44,
          ),
          body: rows(),
        ),
      ),
    );
    expect(
      tester.getCenter(find.byKey(const ValueKey('accessory'))).dy,
      closeTo(tester.getCenter(find.text('精选').first).dy, 2),
    );
  });

  testWidgets('messages badge renders on the bottom navigation', (
    tester,
  ) async {
    Widget nav(int badge) => app(
      Scaffold(
        bottomNavigationBar: AppBottomNavigation(
          current: AppDestination.feed,
          onNavigate: (_) {},
          messagesBadge: badge,
        ),
      ),
    );
    await tester.pumpWidget(nav(3));
    await tester.pumpAndSettle();
    expect(find.text('3'), findsOneWidget);

    await tester.pumpWidget(nav(0));
    await tester.pumpAndSettle();
    expect(find.text('3'), findsNothing);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('shell renders no notification bell', (tester) async {
    await tester.pumpWidget(
      app(
        const AppShell(
          title: '版块',
          current: AppDestination.forums,
          body: SizedBox(),
        ),
      ),
    );
    expect(find.byTooltip('消息'), findsNothing);
    expect(
      File('lib/pages/feed_page.dart').readAsStringSync(),
      isNot(contains('MessagesAction')),
    );
  });
}
