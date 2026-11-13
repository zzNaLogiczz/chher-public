import 'package:chh_app/design/icons.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/ui/grouped.dart';
import 'package:chh_app/widgets/account_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child, {double textScale = 1}) => MaterialApp(
  theme: buildAppTheme(Brightness.light),
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(body: ListView(children: [child])),
    ),
  ),
);

bool paintsPressed(WidgetTester tester, Finder row) => tester
    .widgetList<ColoredBox>(
      find.descendant(of: row, matching: find.byType(ColoredBox)),
    )
    .any((box) => box.color == AppTokens.light.pressed);

void main() {
  testWidgets('read-only rows have no chevron and no press feedback', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const GroupedSection(
          header: '账号资料',
          footer: '资料只读，修改需在网页端进行。',
          children: [GroupedRow(title: '性别', value: '保密')],
        ),
      ),
    );
    expect(find.text('账号资料'), findsOneWidget);
    expect(find.text('资料只读，修改需在网页端进行。'), findsOneWidget);
    expect(find.byIcon(AppIcons.forward), findsNothing);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('性别')),
    );
    await tester.pump();
    expect(paintsPressed(tester, find.byType(GroupedRow)), isFalse);
    await gesture.up();
  });

  testWidgets('a short title leaves the value at the right edge', (
    tester,
  ) async {
    await tester.pumpWidget(app(const GroupedRow(title: 'QQ', value: '未填写')));
    final rowRight = tester.getTopRight(find.byType(GroupedRow)).dx;
    final valueRight = tester.getTopRight(find.text('未填写')).dx;
    expect(valueRight, moreOrLessEquals(rowRight - 12, epsilon: 1));
  });

  testWidgets('tappable rows show a chevron and paint the pressed color', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      app(
        GroupedSection(
          children: [
            GroupedRow(
              title: '设置',
              icon: const IconTile(
                icon: AppIcons.settings,
                tint: IconTints.gray,
              ),
              onTap: () => taps++,
            ),
          ],
        ),
      ),
    );
    expect(find.byIcon(AppIcons.forward), findsOneWidget);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('设置')),
    );
    await tester.pump();
    expect(paintsPressed(tester, find.byType(GroupedRow)), isTrue);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(
      tester.getSize(find.byType(GroupedRow)).height,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('icon tile is a 30dp tinted square with a white glyph', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const Align(
          alignment: Alignment.centerLeft,
          child: IconTile(icon: AppIcons.bookmark, tint: IconTints.orange),
        ),
      ),
    );
    expect(tester.getSize(find.byType(IconTile)), const Size(30, 30));
    expect(
      tester.widget<Icon>(find.byIcon(AppIcons.bookmark)).color,
      Colors.white,
    );
  });

  testWidgets('destructive row is centered red text without chevron', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        GroupedSection(
          children: [GroupedDestructiveRow(label: '退出登录', onTap: () {})],
        ),
      ),
    );
    expect(
      tester.widget<Text>(find.text('退出登录')).style!.color,
      AppTokens.light.red,
    );
    expect(find.byIcon(AppIcons.forward), findsNothing);
    expect(
      tester.getCenter(find.text('退出登录')).dx,
      closeTo(tester.getCenter(find.byType(GroupedDestructiveRow)).dx, 1),
    );
  });

  Widget strip(double scale) => app(
    LacEntryStrip(
      cells: [
        for (final label in ['我的帖子', '我的收藏', '积分记录', '勋章'])
          LacEntryCell(
            icon: AppIcons.articleBold,
            label: label,
            onTap: () {},
          ),
      ],
    ),
    textScale: scale,
  );

  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('lacquer strip keeps four equal columns at ${scale}x text', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(strip(scale));
      final cells = find.byType(LacEntryCell);
      final first = tester.getRect(cells.first);
      for (final cell in cells.evaluate()) {
        final rect = tester.getRect(find.byWidget(cell.widget));
        expect(rect.top, first.top);
        expect(rect.width, first.width);
        expect(rect.height, greaterThanOrEqualTo(44));
      }
      expect(tester.takeException(), isNull);
    });
  }
}
