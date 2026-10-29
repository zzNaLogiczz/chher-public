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

class _ManyStats extends FixtureSpace {
  final Map<String, String> stats;
  _ManyStats(this.stats);
  @override
  Future<UserProfile> profile(String uid, {bool refresh = false}) async =>
      UserProfile(uid: uid, name: '装机爱好者', stats: stats, profile: const {});
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

  testWidgets('user stats show at most three columns, the rest as rows', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        UserPage(
          uid: '42',
          repository: _ManyStats(const {
            '主题': '128',
            '回复': '3600',
            '积分': '900',
            '金钱': '12',
            '威望': '3',
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final bar = find.byKey(UserPage.statsKey);
    expect(bar, findsOneWidget);
    for (final value in ['128', '3600', '900']) {
      expect(
        find.descendant(of: bar, matching: find.text(value)),
        findsOneWidget,
      );
    }
    expect(find.descendant(of: bar, matching: find.text('12')), findsNothing);
    expect(find.widgetWithText(GroupedRow, '金钱'), findsOneWidget);
    expect(find.widgetWithText(GroupedRow, '威望'), findsOneWidget);
  });

  testWidgets('user page hides the stats bar when the source gives none', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(UserPage(uid: '42', repository: _ManyStats(const {}))),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(UserPage.statsKey), findsNothing);
  });

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
