/// 界面风格切换(薄雾白/朱砂红)回归:token 四组合注入、壳分支、
/// 设置页入口,以及薄雾白壳下分段切换不复现灰屏。
library;

import 'package:chh_app/core/appearance.dart';
import 'package:chh_app/data/message_repository.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/di.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/parser/header_parser.dart';
import 'package:chh_app/pages/home_page.dart';
import 'package:chh_app/pages/messages_page.dart';
import 'package:chh_app/pages/settings_page.dart';
import 'package:chh_app/widgets/app_shell.dart';
import 'package:chh_app/widgets/lac_scaffold.dart';
import 'package:chh_app/widgets/large_title_scaffold.dart';
import 'package:chh_app/widgets/launch_splash.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeMessages extends MessageRepository {
  _FakeMessages() : super(ChhClient(fetchers: []));
  @override
  Future<Paged<Notice>> notices({
    NoticeView view = NoticeView.all,
    String? type,
    int page = 1,
    bool refresh = false,
  }) async => Paged(
    items: const [
      Notice(
        id: 'notice-1',
        category: 'post',
        actor: '坛友',
        occurredAtText: '2026-11-10 10:30',
        summary: '坛友回复了你的装机帖',
      ),
    ],
    page: PageInfo(current: page, hasNext: false),
  );

  @override
  Future<Paged<PmConversation>> conversations({
    PmFilter filter = PmFilter.privatePm,
    int page = 1,
    bool refresh = false,
  }) async => Paged(
    items: const [
      PmConversation(
        id: 'conversation-1',
        peer: '对方',
        preview: '最近一条消息',
        timeRaw: '2026-11-10 10:30',
        viewUrl: 'https://www.chiphell.com/home.php?mod=space&do=pm',
      ),
    ],
    page: PageInfo(current: page, hasNext: false),
  );
}

void main() {
  test('tokensFor 四组合返回正确的令牌组', () {
    expect(
      tokensFor(Brightness.light, AppearanceStyle.misty),
      same(AppTokens.mistyLight),
    );
    expect(
      tokensFor(Brightness.dark, AppearanceStyle.misty),
      same(AppTokens.mistyDark),
    );
    expect(
      tokensFor(Brightness.light, AppearanceStyle.cinnabar),
      same(AppTokens.cinnabarLight),
    );
    expect(
      tokensFor(Brightness.dark, AppearanceStyle.cinnabar),
      same(AppTokens.cinnabarDark),
    );
    // 兼容别名保持朱砂红(历史引用点与既有测试依赖)
    expect(AppTokens.light, same(AppTokens.cinnabarLight));
    expect(AppTokens.dark, same(AppTokens.cinnabarDark));
  });

  test('薄雾白令牌组携带风格标记,漆面渐变退化为纸面纯色', () {
    expect(AppTokens.mistyLight.style, AppearanceStyle.misty);
    expect(AppTokens.mistyDark.style, AppearanceStyle.misty);
    expect(AppTokens.cinnabarLight.style, AppearanceStyle.cinnabar);
    // lac 渐变退成 bg 同色;accent 回到 1.0.7 的蓝
    expect(AppTokens.mistyLight.lacTop, AppTokens.mistyLight.bg);
    expect(AppTokens.mistyLight.lacBot, AppTokens.mistyLight.bg);
    expect(AppTokens.mistyLight.accent, const Color(0xFF0D74CE));
    expect(AppTokens.mistyLight.bg, const Color(0xFFFFFFFF));
  });

  testWidgets('buildAppTheme 按风格注入 ThemeExtension', (tester) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light, AppearanceStyle.misty),
        darkTheme: buildAppTheme(Brightness.dark, AppearanceStyle.misty),
        themeMode: ThemeMode.light,
        home: Builder(
          builder: (context) {
            captured = context;
            return const Scaffold(body: SizedBox.shrink());
          },
        ),
      ),
    );
    final t = AppTokens.of(captured);
    expect(t.style, AppearanceStyle.misty);
    expect(t.bg, const Color(0xFFFFFFFF));
  });

  testWidgets('设置页切换界面风格并写回 controller', (tester) async {
    final controller = AppearanceController(directory: () async => null);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: SettingsPage(appearanceController: controller),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('薄雾白'));
    await tester.pumpAndSettle();
    expect(controller.style, AppearanceStyle.misty);

    await tester.tap(find.text('朱砂红'));
    await tester.pumpAndSettle();
    expect(controller.style, AppearanceStyle.cinnabar);
  });

  testWidgets('薄雾白下一级页走纸面骨架,消息分段切换不复现灰屏', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final previousBadges = chhSession.badges;
    addTearDown(() => chhSession.badges = previousBadges);
    chhSession.badges = const HeaderBadges(notices: 3, messages: 2);
    final messages = _FakeMessages();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light, AppearanceStyle.misty),
        home: HomePage(
          initialiseSession: () async {},
          screenBuilders: {
            AppDestination.feed: (_) => const Scaffold(body: Text('本地精选')),
            AppDestination.messages: (_) =>
                MessagesTabPage(repository: messages),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 薄雾白消息页:纸面大标题骨架,漆面骨架不在树上
    await tester.tap(
      find.descendant(
        of: find.byType(AppBottomNavigation),
        matching: find.text('消息'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LargeTitleScaffold), findsOneWidget);
    expect(find.byType(LacScaffold), findsNothing);

    // 交替切分段(灰屏序列)在薄雾白壳下同样安全
    for (var round = 0; round < 3; round++) {
      for (final segment in ['私信', '提醒']) {
        await tester.tap(find.textContaining(segment));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));
        await tester.pump(const Duration(milliseconds: 300));
        final error = tester.takeException();
        if (error != null) fail('segment=$segment round=$round threw: $error');
      }
    }

    // 滚动协调仍在:列表上滑,外层跟随收起
    await tester.drag(find.byType(ListView).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    final outer = tester
        .state<NestedScrollViewState>(find.byType(NestedScrollView))
        .outerController;
    expect(outer.offset, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('薄雾白启动屏用纸面底', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light, AppearanceStyle.misty),
        home: const LaunchSplash(),
      ),
    );
    expect(find.text('chh'), findsOneWidget);
    final context = tester.element(find.text('chh'));
    expect(AppTokens.of(context).style, AppearanceStyle.misty);
  });

  testWidgets('朱砂红启动屏保持漆面渐变', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light, AppearanceStyle.cinnabar),
        home: const LaunchSplash(),
      ),
    );
    final context = tester.element(find.text('chh'));
    expect(AppTokens.of(context).style, AppearanceStyle.cinnabar);
  });
}
