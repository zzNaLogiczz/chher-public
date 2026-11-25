import 'package:chh_app/data/user_block_index.dart';
import 'package:chh_app/design/motion.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/thread_detail_page.dart';
import 'package:chh_app/ui/sheet_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Post _post(int pid, String text, {int? replyTo}) => Post(
  pid: pid,
  floor: pid,
  author: '用户$pid',
  authorUid: '$pid',
  timeRaw: '12:00',
  content: [
    if (replyTo != null)
      QuoteBlock(
        const [TextBlock('原始引用')],
        reference: PostReference(
          tid: 123,
          pid: replyTo,
          url:
              'https://www.chiphell.com/forum.php?mod=redirect&goto=findpost&tid=123&pid=$replyTo',
        ),
      ),
    TextBlock(text),
  ],
);
Future<void> _pump(
  WidgetTester tester,
  UserBlockIndex blocks, {
  BlockedUserSource? source,
  bool settle = true,
  String replyText = '其他人仍然可读',
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      home: ThreadDetailPage(
        tid: 123,
        title: '示例帖子',
        blockIndex: blocks,
        blockedSource: source,
        loadPage: (page, uid, refresh) async => ThreadDetail(
          tid: 123,
          title: '示例帖子',
          fid: 1,
          posts: [
            _post(1, '主帖正文'),
            _post(2, '被屏蔽的正文'),
            _post(3, replyText, replyTo: 2),
            _post(4, '无回复的屏蔽楼层'),
          ],
          page: const PageInfo(current: 1, hasNext: false),
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'blocking root hides its content while preserving another user reply',
    (tester) async {
      final blocks = UserBlockIndex.forTesting(null);
      await blocks.block(uid: '2', name: '用户2');
      await blocks.block(uid: '4', name: '用户4');
      await _pump(tester, blocks);
      expect(find.textContaining('被屏蔽的正文', findRichText: true), findsNothing);
      expect(find.text('已屏蔽用户的发言'), findsOneWidget);
      expect(find.textContaining('无回复的屏蔽楼层', findRichText: true), findsNothing);
      final expand = find.byKey(const ValueKey('thread-expand-replies-2'));
      await tester.ensureVisible(expand);
      await tester.tap(expand);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('其他人仍然可读', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('原始引用', findRichText: true), findsNothing);
      await blocks.unblock('2');
      await tester.pumpAndSettle();
      expect(find.textContaining('被屏蔽的正文', findRichText: true), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      blocks.dispose();
    },
  );
  testWidgets('original floors show blocked reference only once', (
    tester,
  ) async {
    final blocks = UserBlockIndex.forTesting(null);
    await blocks.block(uid: '2', name: '用户2');
    await _pump(tester, blocks);
    await tester.tap(find.byKey(const ValueKey('comment-mode-1')));
    await tester.pumpAndSettle();
    expect(find.text('引用已屏蔽楼层'), findsOneWidget);
    expect(find.textContaining('原始引用', findRichText: true), findsNothing);
    expect(find.text('已屏蔽用户的发言'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    blocks.dispose();
  });
  testWidgets('directly opened blocked topic has an explicit hidden state', (
    tester,
  ) async {
    final blocks = UserBlockIndex.forTesting(null);
    await blocks.block(uid: '1', name: '用户1', note: '原始备注\n保留换行');
    await _pump(tester, blocks);
    expect(find.text('已屏蔽该用户的帖子'), findsOneWidget);
    expect(find.text('原始备注\n保留换行'), findsOneWidget);
    expect(find.textContaining('主帖正文', findRichText: true), findsNothing);
    expect(find.text('解除黑名单'), findsOneWidget);

    await blocks.setUid('901');
    await tester.pumpAndSettle();
    expect(find.text('已屏蔽该用户的帖子'), findsNothing);
    expect(find.text('原始备注\n保留换行'), findsNothing);
    expect(find.textContaining('主帖正文', findRichText: true), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    blocks.dispose();
  });

  for (final pid in [1, 2]) {
    testWidgets('blocked opening highlights source $pid without body text', (
      tester,
    ) async {
      final blocks = UserBlockIndex.forTesting(null);
      await blocks.block(uid: '1', name: '用户1', note: '楼主备注');
      await blocks.block(uid: '2', name: '用户2');
      await _pump(
        tester,
        blocks,
        source: BlockedUserSource(
          tid: 123,
          pid: pid,
          floor: pid,
          title: '示例帖子',
          excerpt: '',
        ),
        settle: false,
      );
      final highlight = find.byKey(ValueKey('blocked-source-highlight-$pid'));
      Color? highlightColor() {
        final box = tester.widgetList<DecoratedBox>(highlight).firstOrNull;
        return (box?.decoration as BoxDecoration?)?.color;
      }

      for (var i = 0; i < 50 && (highlightColor()?.a ?? 0) == 0; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(find.text('已屏蔽 · 用户$pid').hitTestable(), findsOneWidget);
      expect(highlightColor(), isSameColorAs(AppTokens.light.accentFill));
      expect(find.text('楼主备注'), findsOneWidget);
      expect(find.text('解除黑名单'), findsOneWidget);
      expect(find.textContaining('主帖正文', findRichText: true), findsNothing);
      expect(find.textContaining('被屏蔽的正文', findRichText: true), findsNothing);

      await blocks.setUid('901');
      await blocks.block(uid: '1', name: '用户1', note: '另一账号的备注');
      await blocks.block(uid: '2', name: '用户2');
      await tester.pumpAndSettle();
      expect(find.text('另一账号的备注'), findsOneWidget);
      expect(find.text('楼主备注'), findsNothing);
      expect(find.text('已屏蔽 · 用户$pid'), findsNothing);
      expect(highlight, findsNothing);
      await tester.pumpWidget(const SizedBox());
      blocks.dispose();
    });
  }

  for (final reducedMotion in [false, true]) {
    testWidgets(
      'source locates only its folded reply, reduced=$reducedMotion',
      (tester) async {
        final blocks = UserBlockIndex.forTesting(null);
        const source = BlockedUserSource(
          tid: 123,
          pid: 40,
          floor: 40,
          title: '来源帖子',
          excerpt: '来源楼层原文',
        );
        await blocks.block(uid: '40', name: '用户40', src: source);
        await blocks.block(uid: '37', name: '用户37');
        const screen = Size(390, 844);
        tester.view.physicalSize = screen;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var gotoReads = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(Brightness.light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(disableAnimations: reducedMotion),
              child: child!,
            ),
            home: ThreadDetailPage(
              tid: source.tid,
              title: source.title,
              blockIndex: blocks,
              blockedSource: source,
              loadPage: (_, _, _) async => throw StateError('需要按 PID 定位'),
              loadGoto: (url) async {
                gotoReads++;
                expect(Uri.parse(url).queryParameters, {
                  'mod': 'redirect',
                  'goto': 'findpost',
                  'ptid': '123',
                  'pid': '40',
                });
                return ThreadDetail(
                  tid: source.tid,
                  title: source.title,
                  fid: 1,
                  posts: [
                    for (var pid = 21; pid <= 45; pid++)
                      _post(pid, '正文$pid', replyTo: pid == 40 ? 39 : null),
                  ],
                  page: const PageInfo(current: 2, hasNext: false),
                );
              },
            ),
          ),
        );
        final target = find.text('已屏蔽 · 用户40');
        final highlight = find.byKey(
          const ValueKey('blocked-source-highlight-40'),
        );
        for (var i = 0; i < 200 && highlight.evaluate().isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 10));
        }
        Color color() =>
            (tester.widget<DecoratedBox>(highlight).decoration as BoxDecoration)
                .color!;
        expect(gotoReads, 1);
        expect(target.hitTestable(), findsOneWidget);
        expect(
          tester.widget<Text>(target).style?.color,
          AppTokens.light.accent,
        );
        expect(find.text('已屏蔽 · 用户37'), findsNothing);
        expect(find.textContaining('正文40', findRichText: true), findsNothing);
        expect(color(), isSameColorAs(AppTokens.light.accentFill));
        if (reducedMotion) {
          await tester.pump(AppMotion.reducedFade);
        } else {
          await tester.pump(const Duration(milliseconds: 500));
          expect(color(), isSameColorAs(AppTokens.light.accentFill));
          await tester.pump(const Duration(milliseconds: 300));
          expect(color().a, inExclusiveRange(0, AppTokens.light.accentFill.a));
          await tester.pump(const Duration(milliseconds: 800));
        }
        expect(color().a, 0);
        await tester.pumpAndSettle();
        expect(target.hitTestable(), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        blocks.dispose();
      },
    );
  }
  testWidgets(
    'opening action menu has comment and rating without profile item',
    (tester) async {
      final blocks = UserBlockIndex.forTesting(null);
      await _pump(tester, blocks);
      await tester.tap(find.byKey(const ValueKey('post-more-1')));
      await tester.pumpAndSettle();
      Finder menuText(String label) => find.descendant(
        of: find.byType(SheetScaffold),
        matching: find.text(label),
      );
      expect(menuText('点评'), findsOneWidget);
      expect(menuText('评分'), findsOneWidget);
      expect(menuText('复制文字'), findsOneWidget);
      expect(menuText('用户资料'), findsNothing);
      expect(menuText('加入黑名单'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      blocks.dispose();
    },
  );

  testWidgets('floor menu saves its own first 100 characters as source', (
    tester,
  ) async {
    final blocks = UserBlockIndex.forTesting(null);
    final excerpt = '楼内正文'.padRight(100, '甲');
    await _pump(tester, blocks, replyText: '$excerpt。');
    final expand = find.byKey(const ValueKey('thread-expand-replies-2'));
    await tester.ensureVisible(expand);
    await tester.tap(expand);
    await tester.pumpAndSettle();
    final menu = find.byKey(const ValueKey('post-more-3'));
    await tester.ensureVisible(menu);
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('加入黑名单'));
    await tester.pumpAndSettle();
    expect(find.text('来自《示例帖子》', findRichText: true), findsOneWidget);
    await tester.enterText(find.byType(TextField), '保留备注');
    await tester.tap(find.text('加入黑名单'));
    await tester.pumpAndSettle();

    final entry = blocks.entryFor('3');
    expect(entry?.note, '保留备注');
    expect(entry?.src?.tid, 123);
    expect(entry?.src?.pid, 3);
    expect(entry?.src?.floor, 3);
    expect(entry?.src?.title, '示例帖子');
    expect(entry?.src?.excerpt, excerpt);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpWidget(const SizedBox());
    blocks.dispose();
  });
}
