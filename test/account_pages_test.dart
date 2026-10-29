import 'package:chh_app/core/app_log.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/di.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/log_page.dart';
import 'package:chh_app/pages/me_page.dart';
import 'package:chh_app/pages/settings_page.dart';
import 'package:chh_app/parser/header_parser.dart';
import 'package:chh_app/ui/grouped.dart';
import 'package:chh_app/widgets/browse_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/space_fixtures.dart';

void main() {
  testWidgets('guest profile keeps login, settings and diagnostics reachable', (
    tester,
  ) async {
    final wasLoggedIn = chhSession.loggedIn;
    chhSession.loggedIn = false;
    addTearDown(() => chhSession.loggedIn = wasLoggedIn);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        routes: {
          '/login': (_) => const Scaffold(body: Text('LOGIN SCREEN')),
          '/settings': (_) => const Scaffold(body: Text('SETTINGS SCREEN')),
          '/logs': (_) => const Scaffold(body: Text('LOG SCREEN')),
        },
        home: const Scaffold(body: MeBody()),
      ),
    );
    expect(find.text('登录 CHH'), findsOneWidget);
    // 运行日志只保留设置里的入口(规格 §7)
    expect(find.text('运行日志'), findsNothing);
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('SETTINGS SCREEN'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('me shows identity row, four entry tiles and settings only', (
    tester,
  ) async {
    final wasLoggedIn = chhSession.loggedIn;
    final previous = chhSession.badges;
    chhSession.loggedIn = true;
    chhSession.badges = const HeaderBadges(
      notices: 0,
      messages: 0,
      userName: '测试账号',
      uid: '100001',
    );
    addTearDown(() {
      chhSession.loggedIn = wasLoggedIn;
      chhSession.badges = previous;
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: const Scaffold(body: MeBody()),
      ),
    );
    expect(find.text('测试账号'), findsOneWidget);
    expect(find.text('UID 100001'), findsOneWidget);
    expect(find.byType(EntryTile), findsNWidgets(4));
    for (final label in ['我的帖子', '我的收藏', '积分记录', '勋章', '设置']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('运行日志'), findsNothing);
    expect(find.text('退出登录'), findsNothing);
    expect(find.text('个人主页'), findsNothing);
  });

  testWidgets(
    'a privacy select reads as the field visibility, not a twin row',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: SettingsPage(repository: _QqSettings()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('QQ'), findsOneWidget);
      expect(find.text('未填写'), findsOneWidget);
      // 没有 selected 的下拉框在网页上显示第一项
      expect(find.text('QQ 可见范围'), findsOneWidget);
      expect(find.text('公开'), findsOneWidget);
    },
  );

  testWidgets('settings only links to About; update check lives there', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: SettingsPage(repository: FixtureSpace()),
      ),
    );
    await tester.pumpAndSettle();
    final about = find.byKey(const ValueKey('settings-about'));
    await tester.scrollUntilVisible(
      about,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('关于'), findsOneWidget);
    expect(find.text('关于 Chher'), findsOneWidget);
    // 检查更新与安装统计说明都挪进了关于页
    expect(find.text('检查更新'), findsNothing);
    expect(find.textContaining('随机生成的安装标识'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings keeps logout at the bottom behind a confirmation', (
    tester,
  ) async {
    final wasLoggedIn = chhSession.loggedIn;
    chhSession.loggedIn = true;
    addTearDown(() => chhSession.loggedIn = wasLoggedIn);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: SettingsPage(repository: FixtureSpace()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('退出登录'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(
      tester.getTopLeft(find.text('退出登录')).dy,
      greaterThan(tester.getTopLeft(find.text('运行日志')).dy),
    );
    expect(find.byType(GroupedDestructiveRow), findsOneWidget);
    // 只露出一角时点不中,先整行滚进视野
    await tester.ensureVisible(find.text('退出登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();
    expect(find.text('退出当前账号？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(chhSession.loggedIn, isTrue);
  });

  testWidgets(
    'profile values and actions wrap with large text on a narrow screen',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 280,
                  child: SingleChildScrollView(
                    child: GroupedSection(
                      header: '个人资料',
                      children: [
                        const GroupedRow(
                          title: '个人签名',
                          value: '这是一段需要换行的真实个人资料文本',
                        ),
                        GroupedRow(title: '查看我的主题和回复', onTap: () {}),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('这是一段需要换行的真实个人资料文本'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'log severity filter and text search combine without changing records',
    (tester) async {
      AppLog.instance.clear();
      AppLog.i('GET', 'article loaded');
      AppLog.e('NETWORK', 'request failed');
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: const LogPage(),
        ),
      );
      expect(find.text('article loaded'), findsOneWidget);
      expect(find.text('request failed'), findsOneWidget);
      await tester.tap(find.text('只看问题'));
      await tester.pumpAndSettle();
      expect(find.text('article loaded'), findsNothing);
      expect(find.text('request failed'), findsOneWidget);
      await tester.enterText(
        find.descendant(
          of: find.byType(BrowseSearchField),
          matching: find.byType(EditableText),
        ),
        'missing',
      );
      await tester.pumpAndSettle();
      expect(find.text('没有符合条件的日志'), findsOneWidget);
      expect(AppLog.instance.entries.length, 2);
      expect(tester.takeException(), isNull);
      AppLog.instance.clear();
    },
  );
}

/// 源站基本资料页实际结构:qq 输入框 + 没有 selected 的 privacy[qq] 下拉框
class _QqSettings extends FixtureSpace {
  @override
  Future<SettingsForm> settings({
    String ac = 'profile',
    String? op,
    bool refresh = false,
  }) async => const SettingsForm(
    title: '个人资料',
    fields: [
      SettingField(name: 'qq', label: 'QQ', value: ''),
      SettingField(
        name: 'privacy[qq]',
        label: 'QQ',
        value: '',
        options: ['公开', '好友可见', '保密'],
      ),
    ],
  );
}
