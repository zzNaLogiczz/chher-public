/// 界面风格切换(薄暮/朱砂)回归:token 四组合注入、壳分支、
/// 设置页入口,以及薄暮壳下分段切换不复现灰屏。
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
import 'package:chh_app/pages/me_page.dart';
import 'package:chh_app/pages/messages_page.dart';
import 'package:chh_app/pages/settings_page.dart';
import 'package:chh_app/widgets/app_shell.dart';
import 'package:chh_app/ui/chrome_button.dart';
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
    // 兼容别名保持朱砂(历史引用点与既有测试依赖)
    expect(AppTokens.light, same(AppTokens.cinnabarLight));
    expect(AppTokens.dark, same(AppTokens.cinnabarDark));
  });

  test('薄暮令牌组携带风格标记,漆面渐变退化为纸面纯色', () {
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
    expect(AppearanceStyle.misty.label, '薄暮');
    expect(AppearanceStyle.cinnabar.label, '朱砂');
    final controller = AppearanceController(directory: () async => null);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: SettingsPage(appearanceController: controller),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('薄暮'));
    await tester.pumpAndSettle();
    expect(controller.style, AppearanceStyle.misty);

    await tester.tap(find.text('朱砂'));
    await tester.pumpAndSettle();
    expect(controller.style, AppearanceStyle.cinnabar);
  });

  testWidgets('薄暮下一级页走纸面骨架,消息分段切换不复现灰屏', (tester) async {
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

    // 薄暮消息页:纸面大标题骨架,漆面骨架不在树上
    await tester.tap(
      find.descendant(
        of: find.byType(AppBottomNavigation),
        matching: find.text('消息'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LargeTitleScaffold), findsOneWidget);
    expect(find.byType(LacScaffold), findsNothing);

    // 交替切分段(灰屏序列)在薄暮壳下同样安全
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

  testWidgets('薄暮启动屏用纸面底', (tester) async {
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

  testWidgets('朱砂上线引导:设置页内红点可见,离开后永久消失', (tester) async {
    final controller = AppearanceController(directory: () async => null);
    addTearDown(controller.dispose);
    expect(controller.styleDotSeen, isFalse);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light, AppearanceStyle.misty),
        home: SettingsPage(appearanceController: controller),
      ),
    );
    await tester.pumpAndSettle();

    // 设置页内:朱砂选项带引导红点(薄暮没有)
    expect(find.byType(DotBadge), findsOneWidget);

    // 离开设置页(卸载页面)→ 消费引导
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(controller.styleDotSeen, isTrue);

    // 再次进入:红点不再出现
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light, AppearanceStyle.misty),
        home: SettingsPage(appearanceController: controller),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DotBadge), findsNothing);
  });

  testWidgets('我的页设置行在引导未消费时带红点', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light, AppearanceStyle.misty),
        home: const MePage(),
      ),
    );
    await tester.pumpAndSettle();
    final settingsRow = find.byKey(const ValueKey('me-settings'));
    expect(settingsRow, findsOneWidget);
    expect(
      find.descendant(of: settingsRow, matching: find.byType(DotBadge)),
      findsOneWidget,
    );
  });

  testWidgets('底栏我的标签红点随引导消费消失', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light, AppearanceStyle.misty),
        // 四个目的地全部 stub,避免真实页面拉网络;底栏与外观接线保持真实
        home: HomePage(
          initialiseSession: () async {},
          screenBuilders: {
            for (final d in AppDestination.values)
              d: (_) => const SizedBox.shrink(),
          },
        ),
      ),
    );
    // 固定 pump 走过 启动屏→会话就绪→主页 三个状态;这里不用 pumpAndSettle,
    // 全 stub 目的地会让 settle 挂满默认超时(tab_switch_paint_test 有真实
    // 列表内容可 settle,此测试只关心底栏红点参数)
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 未消费:我的标签右上角红点可见
    DotBadge badge = tester.widget<DotBadge>(find.byType(DotBadge));
    expect(badge.visible, isTrue);

    // 消费后立即消失(底栏监听外观偏好)。通知是同步的;不 await 写盘——
    // 全局实例的目录解析走平台通道,测试环境可能没有响应
    appearance.markStyleDotSeen();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));
    badge = tester.widget<DotBadge>(find.byType(DotBadge));
    expect(badge.visible, isFalse);
  });

  testWidgets('朱砂启动屏保持漆面渐变', (tester) async {
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
