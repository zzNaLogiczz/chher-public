/// 真机曾出现的页签切换灰屏回归：版块收起后首次进消息页必须正常绘制。
///
/// 灰屏现场（90.0.37 真机截图）：底栏正常、消息页整页单色灰 (191,183,183)，
/// 漆红渐变/纸面/列表全部无像素。这里用离线假数据重现切换序列，
/// 并直接采样帧像素断言页面真的画了内容。
library;

import 'dart:ui' as ui;

import 'package:chh_app/data/message_repository.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/di.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/parser/header_parser.dart';
import 'package:chh_app/pages/forum_index_view.dart';
import 'package:chh_app/pages/home_page.dart';
import 'package:chh_app/pages/messages_page.dart';
import 'package:chh_app/widgets/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

final GlobalKey _boundary = GlobalKey();

Future<ui.Image> _frame(WidgetTester tester) async {
  final boundary =
      _boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final image = (await tester.runAsync(() => boundary.toImage()))!;
  return image;
}

Future<List<List<int>>> _sampleRows(WidgetTester tester) async {
  final image = await _frame(tester);
  final bytes = await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  );
  final w = image.width;
  final rgba = bytes!.buffer.asUint8List();
  List<int> at(int x, int y) {
    final o = (y * w + x) * 4;
    return [rgba[o], rgba[o + 1], rgba[o + 2]];
  }
  final rows = [at(30, 60), at(30, 120), at(w ~/ 2, 400), at(w ~/ 2, 700)];
  image.dispose();
  return rows;
}

void _expectNotGrey(String where, List<int> px) {
  final isFlatGrey =
      px.every((c) => (c - px.first).abs() < 6) && px.first > 150 && px.first < 230;
  expect(isFlatGrey, isFalse, reason: '$where sampled $px looks like the grey screen');
}

Widget _app(Widget home) => RepaintBoundary(
  key: _boundary,
  child: MaterialApp(theme: buildAppTheme(Brightness.light), home: home),
);

Future<void> _pumpShell(WidgetTester tester, _FakeMessages messages) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final previousBadges = chhSession.badges;
  addTearDown(() => chhSession.badges = previousBadges);
  chhSession.badges = const HeaderBadges(notices: 3, messages: 2);
  await tester.pumpWidget(
    _app(
      HomePage(
        initialiseSession: () async {},
        screenBuilders: {
          AppDestination.feed: (_) => const Scaffold(body: Text('本地精选')),
          AppDestination.forums: (_) => ForumIndexView(
            loadForums: (_) async => [
              ForumCategory(
                name: '交流区',
                forums: List.generate(
                  300,
                  (i) => Forum(fid: i + 1, name: '版块 $i'),
                ),
              ),
            ],
          ),
          AppDestination.messages: (_) =>
              MessagesTabPage(repository: messages),
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(AppBottomNavigation), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('collapsed forums then first visit to messages still paints', (
    tester,
  ) async {
    final messages = _FakeMessages();
    await _pumpShell(tester, messages);

    // 复现真机灰屏序列：打开版块并滚到漆面收起，再首次切到消息
    await _tapTab(tester, '版块');
    await tester.drag(find.byType(CustomScrollView).last, const Offset(0, -650));
    await tester.pumpAndSettle();
    await _tapTab(tester, '消息');

    expect(find.text('消息'), findsWidgets);
    final rows = await _sampleRows(tester);
    // 大标题区应为漆红渐变
    _expectNotGrey('title band', rows[1]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('alternating message segments in tab mode keeps painting', (
    tester,
  ) async {
    // 真机现场:一级页形态下交替点 提醒/私信 数轮后整页单色灰——
    // 根因是显式 controller swap 让普通 position attach 进 NestedScrollView
    // 内层控制器(框架断言,release 下 as 强转抛错炸帧)。
    // 修复后:分段切换只动 PrimaryScrollController(inherited 路径重建 position)。
    final messages = _FakeMessages();
    await _pumpShell(tester, messages);
    await _tapTab(tester, '消息');

    for (var round = 0; round < 4; round++) {
      for (final segment in ['私信', '提醒']) {
        await tester.tap(find.textContaining(segment));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));
        await tester.pump(const Duration(milliseconds: 300));
        final error = tester.takeException();
        if (error != null) fail('segment=$segment round=$round threw: $error');
      }
    }
    final rows = await _sampleRows(tester);
    _expectNotGrey('after alternating segments', rows[2]);

    // 切换协调仍在:列表上滑,漆面头部跟随收起
    await tester.drag(find.byType(ListView).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    final outer = tester
        .state<NestedScrollViewState>(find.byType(NestedScrollView))
        .outerController;
    expect(outer.offset, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid tab cycling keeps every destination painted', (tester) async {
    final messages = _FakeMessages();
    await _pumpShell(tester, messages);

    for (var round = 0; round < 3; round++) {
      for (final label in ['版块', '消息', '我的', '精选']) {
        await tester.tap(
          find.descendant(
            of: find.byType(AppBottomNavigation),
            matching: find.text(label),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        await tester.pump(const Duration(milliseconds: 200));
        final rows = await _sampleRows(tester);
        _expectNotGrey('$label round $round full frame', rows[2]);
        expect(tester.takeException(), isNull);
      }
    }
  });
}
