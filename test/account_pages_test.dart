import 'package:chh_app/core/app_log.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/di.dart';
import 'package:chh_app/pages/log_page.dart';
import 'package:chh_app/pages/me_page.dart';
import 'package:chh_app/pages/settings_page.dart';
import 'package:chh_app/parser/header_parser.dart';
import 'package:chh_app/ui/grouped.dart';
import 'package:chh_app/widgets/browse_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

  for (final loggedIn in [true, false]) {
    testWidgets(
      'settings groups follow task order without a repository, loggedIn=$loggedIn',
      (tester) async {
        final wasLoggedIn = chhSession.loggedIn;
        chhSession.loggedIn = loggedIn;
        addTearDown(() => chhSession.loggedIn = wasLoggedIn);
        await tester.binding.setSurfaceSize(const Size(400, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(Brightness.light),
            home: const SettingsPage(),
          ),
        );
        await tester.pumpAndSettle();

        final sections = tester.widgetList<GroupedSection>(
          find.byType(GroupedSection),
        );
        expect(sections.map((section) => section.header), [
          '存储',
          '关于',
          if (loggedIn) null,
        ]);
        final storage = find.byWidgetPredicate(
          (widget) => widget is GroupedSection && widget.header == '存储',
        );
        final about = find.byWidgetPredicate(
          (widget) => widget is GroupedSection && widget.header == '关于',
        );
        expect(
          tester
              .widgetList<GroupedRow>(
                find.descendant(of: storage, matching: find.byType(GroupedRow)),
              )
              .map((row) => row.title),
          ['图片缓存'],
        );
        expect(
          tester
              .widgetList<GroupedRow>(
                find.descendant(of: about, matching: find.byType(GroupedRow)),
              )
              .map((row) => row.title),
          ['关于 Chher', '运行日志'],
        );
        final labels = ['外观', '存储', '关于', if (loggedIn) '退出登录'];
        for (var i = 1; i < labels.length; i++) {
          expect(
            tester.getTopLeft(find.text(labels[i - 1])).dy,
            lessThan(tester.getTopLeft(find.text(labels[i])).dy),
          );
        }
        expect(find.text('退出登录'), loggedIn ? findsOneWidget : findsNothing);
        expect(find.text('账号资料'), findsNothing);
        expect(find.text('诊断'), findsNothing);
        expect(find.text('加载失败'), findsNothing);
        expect(find.text('需登录'), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('运行日志'));
        await tester.pumpAndSettle();
        expect(find.byType(LogPage), findsOneWidget);
      },
    );
  }

  testWidgets('退出登录分组随会话变化显示，其他设置不重建', (tester) async {
    final wasLoggedIn = chhSession.loggedIn;
    chhSession.loggedIn = true;
    addTearDown(() => chhSession.loggedIn = wasLoggedIn);
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: const SettingsPage(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('退出登录'), findsOneWidget);
    final list = tester.widget<ListView>(find.byType(ListView));
    final about = tester.widget(find.byKey(const ValueKey('settings-about')));

    void changeSession(bool loggedIn) {
      chhSession.loggedIn = loggedIn;
      // 模拟会话完成登录或退出后的通知,不调用平台 Cookie 仓。
      // ignore: invalid_use_of_protected_member
      chhSession.notifyListeners();
    }

    changeSession(false);
    await tester.pumpAndSettle();
    expect(find.text('退出登录'), findsNothing);
    expect(find.byType(GroupedSection), findsNWidgets(2));
    expect(tester.widget<ListView>(find.byType(ListView)), same(list));
    expect(
      tester.widget(find.byKey(const ValueKey('settings-about'))),
      same(about),
    );

    changeSession(true);
    await tester.pumpAndSettle();
    expect(find.text('退出登录'), findsOneWidget);
    expect(find.byType(GroupedSection), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings only links to About; update check lives there', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: const SettingsPage(),
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
        home: const SettingsPage(),
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
