import 'package:chh_app/data/user_block_index.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/thread_detail_page.dart';
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
Future<void> _pump(WidgetTester tester, UserBlockIndex blocks) async {
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
        loadPage: (page, uid, refresh) async => ThreadDetail(
          tid: 123,
          title: '示例帖子',
          fid: 1,
          posts: [
            _post(1, '主帖正文'),
            _post(2, '被屏蔽的正文'),
            _post(3, '其他人仍然可读', replyTo: 2),
            _post(4, '无回复的屏蔽楼层'),
          ],
          page: const PageInfo(current: 1, hasNext: false),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'blocking root hides its content while preserving another user reply',
    (tester) async {
      final blocks = UserBlockIndex(null);
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
    final blocks = UserBlockIndex(null);
    await blocks.block(uid: '2', name: '用户2');
    await _pump(tester, blocks);
    await tester.tap(find.text('原楼层'));
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
    final blocks = UserBlockIndex(null);
    await blocks.block(uid: '1', name: '用户1');
    await _pump(tester, blocks);
    expect(find.text('已屏蔽该用户的帖子'), findsOneWidget);
    expect(find.textContaining('主帖正文', findRichText: true), findsNothing);
    expect(find.text('解除黑名单'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    blocks.dispose();
  });
  testWidgets(
    'opening action menu has comment and rating without profile item',
    (tester) async {
      final blocks = UserBlockIndex(null);
      await _pump(tester, blocks);
      await tester.tap(find.byKey(const ValueKey('post-more-1')));
      await tester.pumpAndSettle();
      expect(find.text('点评'), findsOneWidget);
      expect(find.text('评分'), findsOneWidget);
      expect(find.text('用户资料'), findsNothing);
      expect(find.text('加入黑名单'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      blocks.dispose();
    },
  );
}
