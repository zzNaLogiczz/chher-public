import 'dart:async';

import 'package:chh_app/data/user_group_levels.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/my_threads_page.dart';
import 'package:chh_app/pages/user_drawer.dart';
import 'package:chh_app/pages/user_page.dart';
import 'package:chh_app/ui/chrome_button.dart';
import 'package:chh_app/ui/grouped.dart';
import 'package:chh_app/ui/nav_bar.dart';
import 'package:chh_app/widgets/expressive_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/space_fixtures.dart';

class _ProfileSpace extends FixtureSpace {
  final Future<UserProfile> Function(bool refresh) load;
  final refreshes = <bool>[];
  _ProfileSpace(this.load);

  @override
  Future<UserProfile> profile(String uid, {bool refresh = false}) {
    refreshes.add(refresh);
    return load(refresh);
  }
}

Widget _app(
  Widget page, {
  Brightness brightness = Brightness.light,
  double textScale = 1,
  bool disableAnimations = false,
}) => MaterialApp(
  theme: buildAppTheme(brightness),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(textScale),
      disableAnimations: disableAnimations,
    ),
    child: child!,
  ),
  home: page,
);

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('个人主页按身份、数据、帖子、资料组织内容', (tester) async {
    _size(tester, const Size(400, 1600));
    final repo = FixtureSpace();
    await tester.pumpWidget(_app(UserPage(uid: '42', repository: repo)));
    await tester.pumpAndSettle();
    final sections = [
      find.byKey(UserPage.identityKey),
      find.byKey(UserPage.statsKey),
      find.byKey(UserPage.threadsKey),
      find.byWidgetPredicate((w) => w is GroupedSection && w.header == '资料'),
    ];
    for (var i = 0; i < sections.length; i++) {
      expect(sections[i], findsOneWidget);
      if (i > 0) {
        expect(
          tester.getTopLeft(sections[i - 1]).dy,
          lessThan(tester.getTopLeft(sections[i]).dy),
        );
      }
    }
    expect(find.text('权天使'), findsOneWidget);
    expect(find.text('在线时长'), findsOneWidget);
    expect(find.text('2845'), findsOneWidget);
    expect(find.text('小时'), findsOneWidget);
    expect(find.text('主题 128，回帖 3600'), findsOneWidget);
    final rows = tester
        .widgetList<GroupedRow>(find.byType(GroupedRow))
        .toList();
    expect(rows.map((row) => row.title), ['注册时间', '最后访问', '上次发表', '好友']);
    expect(rows.map((row) => row.value), [
      '2013-6-1 21:59',
      '2026-10-30 11:43',
      '2026-10-29 22:46',
      '15',
    ]);
    for (final row in rows) {
      expect(row.icon, isNull);
      expect(row.leading, isNull);
      expect(row.onTap, isNull);
    }
    for (final text in [
      '个人主页',
      '已用空间',
      '所在时区',
      '邮箱状态',
      '上次活动时间',
      '统计信息',
      '用户认证',
    ]) {
      expect(find.text(text), findsNothing);
    }
    expect(find.byType(IconTile), findsNothing);
    expect(find.byType(ExpressivePageReveal), findsWidgets);
    await tester.tap(find.text('主题与回复'));
    await tester.pumpAndSettle();
    final page = tester.widget<MyThreadsPage>(find.byType(MyThreadsPage));
    expect(page.uid, '42');
    expect(page.title, '装机爱好者');
    expect(page.repository, same(repo));
    for (final label in ['主题', '回复', '点评']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(repo.threadRequests, ['thread']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('缺失资料只保留身份与帖子入口，不编造数字', (tester) async {
    await tester.pumpWidget(
      _app(
        UserPage(
          uid: '42',
          repository: _ProfileSpace(
            (_) async => const UserProfile(
              uid: '42',
              name: '访客',
              profile: {
                '邮箱状态': '已验证',
                '所在时区': '(GMT +08:00) 北京, 香港',
                '上次活动时间': '2026-10-30 11:43',
                '统计信息': '好友数 15 | 回帖数 3112 | 主题数 616',
                '用户认证': '手机认证',
              },
              stats: {'已用空间': '0 B'},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(UserPage.identityKey), findsOneWidget);
    expect(find.text('UID 42'), findsOneWidget);
    expect(find.byKey(UserPage.threadsKey), findsOneWidget);
    expect(find.byKey(UserPage.statsKey), findsNothing);
    expect(find.byType(GroupedSection), findsNothing);
    for (final text in [
      '在线时长',
      '积分',
      '邪恶指数',
      '差 0 积分',
      '资料',
      '0',
      '邮箱状态',
      '所在时区',
      '上次活动时间',
      '统计信息',
      '用户认证',
      '已用空间',
      '已验证',
      '手机认证',
      '0 B',
      '好友数 15 | 回帖数 3112 | 主题数 616',
    ]) {
      expect(find.text(text), findsNothing);
    }
    expect(find.textContaining('主题 '), findsNothing);
    expect(find.textContaining('回帖 '), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('身份元信息按 UID、用户组、进度、差额排列，积分列无进度', (tester) async {
    _size(tester, const Size(800, 900));
    final levels = _GroupLevels((_) async => 2500);
    await tester.pumpWidget(
      _app(
        UserPage(
          uid: '900001',
          groupLevels: levels,
          repository: _ProfileSpace((_) async => _progressProfile),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final order = [
      find.text('UID 900001'),
      find.text('能天使'),
      find.byKey(UserPage.progressKey),
      find.text('差 1120 积分'),
    ];
    for (var i = 0; i < order.length; i++) {
      expect(order[i], findsOneWidget);
      if (i > 0) {
        expect(
          tester.getCenter(order[i - 1]).dx,
          lessThan(tester.getCenter(order[i]).dx),
        );
      }
    }
    final progress = tester.widget<Semantics>(find.byKey(UserPage.progressKey));
    expect(progress.properties.label, '升级进度');
    expect(progress.properties.value, '差 1120 积分');
    expect(tester.getSize(find.byKey(UserPage.progressKey)), const Size(56, 4));
    expect(_progressFactor(tester), closeTo(380 / 1500, .0001));
    expect(levels.requests, [41]);
    expect(
      find.descendant(
        of: find.byKey(UserPage.statsKey),
        matching: find.byType(TweenAnimationBuilder<double>),
      ),
      findsNothing,
    );
    expect(find.byType(IconTile), findsNothing);
    final identityBoxes = tester.widgetList<DecoratedBox>(
      find.descendant(
        of: find.byKey(UserPage.identityKey),
        matching: find.byType(DecoratedBox),
      ),
    );
    expect(
      identityBoxes.where(
        (box) =>
            box.decoration is BoxDecoration &&
            (box.decoration as BoxDecoration).gradient != null,
      ),
      isEmpty,
    );
  });

  for (final group in <String?>[null, '', '特殊组']) {
    testWidgets('用户组=$group 时省略不适用的升级信息', (tester) async {
      final levels = _GroupLevels((_) async => 2500);
      await tester.pumpWidget(
        _app(
          UserPage(
            uid: '42',
            groupLevels: levels,
            repository: _ProfileSpace(
              (_) async => UserProfile(
                uid: '42',
                name: '用户',
                group: group,
                groupId: 41,
                credits: 2880,
                nextLevelCredits: group == '特殊组' ? null : 1120,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('UID 42'), findsOneWidget);
      expect(find.byKey(UserPage.progressKey), findsNothing);
      expect(find.text('差 1120 积分'), findsNothing);
      expect(
        find.byIcon(AppIcons.crownStar),
        group == '特殊组' ? findsOneWidget : findsNothing,
      );
      expect(levels.requests, isEmpty);
    });
  }

  for (final lower in <int?>[null, 2500]) {
    testWidgets('等级下限异步返回 $lower，首屏先显示底槽和差额', (tester) async {
      final result = Completer<int?>();
      await tester.pumpWidget(
        _app(
          UserPage(
            uid: '900001',
            groupLevels: _GroupLevels((_) => result.future),
            repository: _ProfileSpace((_) async => _progressProfile),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('差 1120 积分'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(_progressFactor(tester), 0);
      result.complete(lower);
      await tester.pump();
      await tester.pump();
      if (lower != null) {
        await tester.pump(const Duration(milliseconds: 100));
        expect(_progressFactor(tester), greaterThan(0));
        expect(_progressFactor(tester), lessThan(380 / 1500));
      }
      await tester.pumpAndSettle();
      expect(
        _progressFactor(tester),
        lower == null ? 0 : closeTo(380 / 1500, .0001),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('减少动态效果时等级进度直接到位', (tester) async {
    final result = Completer<int?>();
    await tester.pumpWidget(
      _app(
        UserPage(
          uid: '900001',
          groupLevels: _GroupLevels((_) => result.future),
          repository: _ProfileSpace((_) async => _progressProfile),
        ),
        disableAnimations: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(_progressFactor(tester), 0);
    result.complete(2500);
    await tester.pump();
    await tester.pump();
    expect(_progressFactor(tester), closeTo(380 / 1500, .0001));
    expect(tester.takeException(), isNull);
  });

  for (final threads in [true, false]) {
    testWidgets('帖子副标题仅展示已知${threads ? '主题' : '回帖'}数', (tester) async {
      await tester.pumpWidget(
        _app(
          UserPage(
            uid: '42',
            repository: _ProfileSpace(
              (_) async => UserProfile(
                uid: '42',
                name: '用户',
                threads: threads ? 0 : null,
                replies: threads ? null : 16,
                friends: 0,
                portalArticles: 3,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(threads ? '主题 0' : '回帖 16'), findsOneWidget);
      expect(find.text('门户文章'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('好友'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets('320dp、两倍字号、$brightness 下长名字和大数字不溢出', (tester) async {
      _size(tester, const Size(320, 844));
      await tester.pumpWidget(
        _app(
          UserPage(
            uid: '900001',
            repository: _ProfileSpace(
              (_) async => const UserProfile(
                uid: '900001',
                name: '一位名字很长很长很长的装机爱好者',
                group: '一位资深且热心的权天使',
                onlineHours: 9999999999999999,
                credits: 9999999999999999,
                nextLevelCredits: 9999999999999999,
                evil: 9999999999999999,
                threads: 9999999999999999,
                replies: 9999999999999999,
                friends: 9999999999999999,
                registeredAt: '2013-6-1 21:59',
                lastVisitAt: '2026-10-30 11:43',
                lastPostAt: '2026-10-29 22:46',
                portalArticles: 9999999999999999,
              ),
            ),
          ),
          brightness: brightness,
          textScale: 2,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (var i = 0; i < 5; i++) {
        await tester.drag(find.byType(ListView), const Offset(0, -450));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(find.text('门户文章'), findsOneWidget);
    });
  }

  testWidgets('滚过身份卡后顶栏显示用户名，返回按钮始终可用', (tester) async {
    _size(tester, const Size(400, 500));
    await tester.pumpWidget(
      _app(UserPage(uid: '42', repository: FixtureSpace())),
    );
    await tester.pumpAndSettle();
    final title = find.byKey(NavOverlay.inlineTitleKey);
    expect(tester.widget<Opacity>(title).opacity, 0);
    expect(find.byTooltip('返回'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(tester.widget<Opacity>(title).opacity, 1);
    expect(
      find.descendant(of: title, matching: find.text('装机爱好者')),
      findsOneWidget,
    );
    expect(find.byTooltip('返回'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('抽屉加载前标题空白，加载后显示用户名并保留关闭按钮', (tester) async {
    final result = Completer<UserProfile>();
    await tester.pumpWidget(
      _app(
        UserDrawer(uid: '42', repository: _ProfileSpace((_) => result.future)),
      ),
    );
    expect(find.text('个人主页'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byTooltip('关闭'), findsOneWidget);
    result.complete(const UserProfile(uid: '42', name: '离线用户'));
    await tester.pumpAndSettle();
    expect(find.text('离线用户'), findsNWidgets(2));
    expect(find.byTooltip('关闭'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('刷新重新读取资料并更新身份', (tester) async {
    final repo = _ProfileSpace(
      (refresh) async =>
          UserProfile(uid: '42', name: refresh ? '刷新后的名字' : '初始名字'),
    );
    await tester.pumpWidget(_app(UserPage(uid: '42', repository: repo)));
    await tester.pumpAndSettle();
    expect(find.text('初始名字'), findsWidgets);
    await tester.drag(find.byType(ListView), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(repo.refreshes, [false, true]);
    expect(find.text('刷新后的名字'), findsWidgets);
    expect(find.text('初始名字'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('加载失败允许重试，随后显示真实资料', (tester) async {
    var calls = 0;
    final repo = _ProfileSpace((_) async {
      if (calls++ == 0) throw StateError('offline failure');
      return const UserProfile(uid: '42', name: '重试成功');
    });
    await tester.pumpWidget(_app(UserPage(uid: '42', repository: repo)));
    await tester.pumpAndSettle();
    expect(find.text('加载失败'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('重试成功'), findsWidgets);
    expect(repo.refreshes, [false, true]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('登录墙保留登录操作', (tester) async {
    await tester.pumpWidget(
      _app(
        UserPage(
          uid: '42',
          repository: _ProfileSpace(
            (_) async =>
                throw const PageMessage(PageMessageKind.loginRequired, '登录'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('需登录'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
    expect(find.byType(ChromeButton), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

const _progressProfile = UserProfile(
  uid: '900001',
  name: '示例用户',
  group: '能天使',
  groupId: 41,
  credits: 2880,
  nextLevelCredits: 1120,
);

class _GroupLevels extends UserGroupLevels {
  final Future<int?> Function(int gid) lookup;
  final requests = <int>[];
  _GroupLevels(this.lookup) : super(ChhClient(fetchers: []));

  @override
  Future<int?> lowerCredits(int gid) {
    requests.add(gid);
    return lookup(gid);
  }
}

double _progressFactor(WidgetTester tester) => tester
    .widget<FractionallySizedBox>(
      find.descendant(
        of: find.byKey(UserPage.progressKey),
        matching: find.byType(FractionallySizedBox),
      ),
    )
    .widthFactor!;
