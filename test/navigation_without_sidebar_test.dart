import 'package:chh_app/app.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/di.dart';
import 'package:chh_app/pages/me_page.dart';
import 'package:chh_app/widgets/app_shell.dart';
import 'package:chh_app/ui/grouped.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the primary shell has no navigation drawer or menu switch', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: AppShell(
          title: '版块',
          current: AppDestination.forums,
          body: ListView(children: const [Text('版块内容')]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(AppDestination.values, [
      AppDestination.feed,
      AppDestination.forums,
      AppDestination.messages,
      AppDestination.me,
    ]);
    expect(find.byType(Drawer), findsNothing);
    expect(find.byType(DrawerButton), findsNothing);
    expect(find.byTooltip('导航'), findsNothing);
    for (final scaffold in tester.widgetList<Scaffold>(find.byType(Scaffold))) {
      expect(scaffold.drawer, isNull);
      expect(scaffold.endDrawer, isNull);
    }
    await tester.dragFrom(const Offset(1, 300), const Offset(240, 0));
    await tester.pumpAndSettle();
    expect(find.text('版块内容'), findsOneWidget);
    expect(find.byType(Drawer), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('personal tools and their business routes remain available', (
    tester,
  ) async {
    final previous = chhSession.loggedIn;
    chhSession.loggedIn = true;
    addTearDown(() => chhSession.loggedIn = previous);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: const Scaffold(body: MeBody()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(EntryTile, '我的收藏'), findsOneWidget);
    // 运行日志从"我的"移到设置页内,路由保持可达(见下方 routes 断言)
    await tester.scrollUntilVisible(
      find.text('设置'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.widgetWithText(GroupedRow, '设置'), findsOneWidget);
    await tester.pumpWidget(const ChhApp());
    final application = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(
      application.routes?.keys,
      containsAll(['/favorites', '/settings', '/logs']),
    );
    expect(tester.takeException(), isNull);
  });
}
