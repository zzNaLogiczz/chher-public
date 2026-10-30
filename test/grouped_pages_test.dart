import 'package:chh_app/data/space_repository.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/credit_log_page.dart';
import 'package:chh_app/pages/forum_index_view.dart';
import 'package:chh_app/pages/log_page.dart';
import 'package:chh_app/pages/user_page.dart';
import 'package:chh_app/ui/grouped.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/space_fixtures.dart';

Widget app(Widget home) =>
    MaterialApp(theme: buildAppTheme(Brightness.light), home: home);

class _ProfileStats extends FixtureSpace {
  final int? onlineHours;
  final int? credits;
  final int? evil;
  _ProfileStats({this.onlineHours, this.credits, this.evil});
  @override
  Future<UserProfile> profile(String uid, {bool refresh = false}) async =>
      UserProfile(
        uid: uid,
        name: '装机爱好者',
        onlineHours: onlineHours,
        credits: credits,
        evil: evil,
      );
}

class _SignedCredits extends FixtureSpace {
  @override
  Future<SiteTable> creditLog({int page = 1, bool refresh = false}) async =>
      const SiteTable(
        headers: ['操作', '积分变更', '时间'],
        rows: [
          ['发表回复', '+10', '2026-10-26 12:30'],
          ['购买附件', '-5', '2026-10-25 09:15'],
        ],
      );
}

void main() {
  testWidgets('forum index rows show topic counts without leading icons', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        Scaffold(
          body: ForumIndexView(
            loadForums: (_) async => const [
              ForumCategory(
                name: '互动区-勋章和活动的会场',
                forums: [Forum(fid: 1, name: '勋章申请区', threadCount: 2)],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 个主题'), findsOneWidget);
    final row = find.widgetWithText(GroupedRow, '勋章申请区');
    expect(row, findsOneWidget);
    expect(tester.widget<GroupedRow>(row).icon, isNull);
    expect(tester.widget<GroupedRow>(row).leading, isNull);
  });

  testWidgets(
    'user statistics share one neutral surface with three equal columns',
    (tester) async {
      await tester.pumpWidget(
        app(UserPage(uid: '42', repository: FixtureSpace())),
      );
      await tester.pumpAndSettle();
      final cards = find.byKey(UserPage.statsKey);
      expect(cards, findsOneWidget);
      final online = find.descendant(of: cards, matching: find.text('在线时长'));
      final credits = find.descendant(of: cards, matching: find.text('积分'));
      final evil = find.descendant(of: cards, matching: find.text('邪恶指数'));
      expect(credits, findsOneWidget);
      expect(evil, findsOneWidget);
      expect(tester.getTopLeft(credits).dy, tester.getTopLeft(evil).dy);
      final surfaces = find.descendant(
        of: cards,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox && widget.decoration is ShapeDecoration,
        ),
      );
      expect(surfaces, findsOneWidget);
      expect(tester.getTopLeft(online).dy, tester.getTopLeft(credits).dy);
      final columns = find.descendant(
        of: cards,
        matching: find.byType(Expanded),
      );
      expect(columns, findsNWidgets(3));
      for (var i = 1; i < 3; i++) {
        expect(tester.getSize(columns.at(i)), tester.getSize(columns.first));
      }
      expect(
        find.descendant(of: cards, matching: find.byType(VerticalDivider)),
        findsNWidgets(2),
      );
      expect(find.text('差 171 积分'), findsOneWidget);
      expect(
        find.descendant(of: cards, matching: find.byKey(UserPage.progressKey)),
        findsNothing,
      );
      expect(find.widgetWithText(GroupedRow, '金钱'), findsNothing);
      expect(find.widgetWithText(GroupedRow, '威望'), findsNothing);
    },
  );

  for (var mask = 0; mask < 8; mask++) {
    final onlineHours = mask & 1 != 0 ? 12 : null;
    final credits = mask & 2 != 0 ? 900 : null;
    final evil = mask & 4 != 0 ? 800 : null;
    final count = [onlineHours, credits, evil].whereType<int>().length;
    testWidgets(
      'user statistics omit missing columns, hours=$onlineHours, credits=$credits, evil=$evil',
      (tester) async {
        await tester.pumpWidget(
          app(
            UserPage(
              uid: '42',
              repository: _ProfileStats(
                onlineHours: onlineHours,
                credits: credits,
                evil: evil,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(UserPage.statsKey),
          count == 0 ? findsNothing : findsOneWidget,
        );
        expect(
          find.text('在线时长'),
          onlineHours == null ? findsNothing : findsOneWidget,
        );
        expect(find.text('邪恶指数'), evil == null ? findsNothing : findsOneWidget);
        expect(
          find.text('积分'),
          credits == null ? findsNothing : findsOneWidget,
        );
        if (count > 0) {
          final cards = find.byKey(UserPage.statsKey);
          expect(tester.getSize(cards).width, 800 - AppSpace.groupInset * 2);
          final columns = find.descendant(
            of: cards,
            matching: find.byType(Expanded),
          );
          expect(columns, findsNWidgets(count));
          for (var i = 1; i < count; i++) {
            expect(
              tester.getSize(columns.at(i)),
              tester.getSize(columns.first),
            );
          }
          expect(
            find.descendant(of: cards, matching: find.byType(VerticalDivider)),
            findsNWidgets(count - 1),
          );
        }
      },
    );
  }

  testWidgets('credit amounts keep their sign and are colored by direction', (
    tester,
  ) async {
    await tester.pumpWidget(app(CreditLogPage(repository: _SignedCredits())));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.text('+10')).style!.color,
      AppTokens.light.green,
    );
    expect(
      tester.widget<Text>(find.text('-5')).style!.color,
      AppTokens.light.red,
    );
  });

  testWidgets('log actions are reachable from one chrome group', (
    tester,
  ) async {
    await tester.pumpWidget(app(const LogPage()));
    await tester.pumpAndSettle();
    for (final tip in ['复制当前列表', '导出全部日志', '清空日志']) {
      expect(find.byTooltip(tip), findsOneWidget, reason: tip);
    }
    expect(find.byType(PopupMenuButton<String>), findsNothing);
  });

  test('fixture space repository type stays the account fixture', () {
    expect(FixtureSpace(), isA<SpaceRepository>());
  });
}
