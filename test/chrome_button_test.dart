import 'package:chh_app/design/icons.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/ui/chrome_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solar_icons/solar_icons.dart';

Widget app(Widget child) => MaterialApp(
  theme: buildAppTheme(Brightness.light),
  home: Scaffold(body: Center(child: child)),
);

BoxDecoration decorationOf(WidgetTester tester, Key key) =>
    tester.widget<DecoratedBox>(find.byKey(key)).decoration as BoxDecoration;

void main() {
  test('chrome icons are outline glyphs, tab icons stay bold', () {
    expect(AppIcons.search, SolarIconsOutline.magnifier);
    expect(AppIcons.back, SolarIconsOutline.altArrowLeft);
    expect(AppIcons.tabHome, SolarIconsBold.home2);
    expect(AppIcons.tabMessages, SolarIconsBold.chatRoundDots);
  });

  testWidgets('chrome button is a 38dp glass circle with a 44dp hit area', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(ChromeButton(icon: AppIcons.search, tooltip: '搜索', onPressed: () {})),
    );
    expect(tester.getSize(find.byType(ChromeButton)), const Size(44, 44));
    expect(
      tester.getSize(find.byKey(ChromeButton.surfaceKey)),
      const Size(38, 38),
    );
    final circle = decorationOf(tester, ChromeButton.surfaceKey);
    expect(circle.color, AppTokens.light.glass);
    expect(circle.shape, BoxShape.circle);
    expect(circle.boxShadow, AppTokens.light.shadowE1);
    expect(find.byTooltip('搜索'), findsOneWidget);
  });

  testWidgets('on-image variant uses image glass and white icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        ChromeButton(
          icon: AppIcons.close,
          tooltip: '关闭',
          onImage: true,
          onPressed: () {},
        ),
      ),
    );
    expect(
      decorationOf(tester, ChromeButton.surfaceKey).color,
      AppTokens.light.glassOnImage,
    );
    expect(
      tester.widget<Icon>(find.byIcon(AppIcons.close)).color,
      Colors.white,
    );
  });

  testWidgets('selected chrome button tints the icon with accent', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        ChromeButton(
          icon: AppIcons.views,
          tooltip: '放大字号',
          selected: true,
          onPressed: () {},
        ),
      ),
    );
    expect(
      tester.widget<Icon>(find.byIcon(AppIcons.views)).color,
      AppTokens.light.accent,
    );
  });

  testWidgets('group places actions in one 38dp capsule', (tester) async {
    var searched = 0;
    await tester.pumpWidget(
      app(
        ChromeGroup(
          items: [
            ChromeGroupItem(
              icon: AppIcons.search,
              tooltip: '搜索帖子',
              onPressed: () => searched++,
            ),
            ChromeGroupItem(
              icon: AppIcons.compose,
              tooltip: '发主题',
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
    expect(find.byKey(ChromeGroup.surfaceKey), findsOneWidget);
    expect(
      tester.getSize(find.byKey(ChromeGroup.surfaceKey)),
      const Size(2 * 38 + 8, 38),
    );
    expect(
      decorationOf(tester, ChromeGroup.surfaceKey).color,
      AppTokens.light.glass,
    );
    await tester.tap(find.byTooltip('搜索帖子'));
    expect(searched, 1);
    expect(find.byTooltip('发主题'), findsOneWidget);
  });

  testWidgets('badge shows the count and hides at zero', (tester) async {
    Widget button(int count) => app(
      ChromeButton(
        icon: AppIcons.notification,
        tooltip: '消息',
        badgeCount: count,
        onPressed: () {},
      ),
    );
    await tester.pumpWidget(button(3));
    await tester.pumpAndSettle();
    expect(find.text('3'), findsOneWidget);
    final badge = decorationOf(tester, CountBadge.surfaceKey);
    expect(badge.color, AppTokens.light.red);

    await tester.pumpWidget(button(0));
    await tester.pumpAndSettle();
    expect(find.text('0'), findsNothing);
    expect(find.text('3'), findsNothing);
  });

  testWidgets('neutral badge uses text color fill', (tester) async {
    await tester.pumpWidget(
      app(const CountBadge(count: 65, tone: BadgeTone.neutral)),
    );
    await tester.pumpAndSettle();
    expect(
      decorationOf(tester, CountBadge.surfaceKey).color,
      AppTokens.light.text,
    );
    expect(
      tester.widget<Text>(find.text('65')).style!.color,
      AppTokens.light.bg,
    );
  });
}
