import 'package:chh_app/data/article_comment_index.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/models/article_discussion.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/article_discussion_page.dart';
import 'package:chh_app/parser/portal_parser.dart';
import 'package:chh_app/ui/segmented.dart';
import 'package:chh_app/widgets/article_discussion_widgets.dart';
import 'package:chh_app/widgets/comment_mode_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ArticleComment comment(
  int cid,
  String author,
  String text, {
  String? quote,
  String? uid,
}) => ArticleComment(
  cid: cid,
  author: author,
  authorUid: uid,
  text: text,
  content: [
    if (quote != null) QuoteBlock([TextBlock(quote)]),
    TextBlock(text),
  ],
);

// 源站评论按时间倒序:新的在前
final items = [
  comment(15, '作者甲', '谢谢补充', quote: '读者乙: 第二槽还有4cm空间', uid: 'a'),
  comment(14, '读者戊', '引用了不存在的话', quote: '作者甲: 从没说过这句'),
  comment(13, '读者丁', '独立评论'),
  comment(12, '读者丙', '那第三槽呢', quote: '读者乙: 第二槽还有4cm空间'),
  comment(11, '读者乙', '第二槽还有4cm空间', quote: '作者甲: 第二卡还有空间嘛？'),
  comment(10, '作者甲', '第二卡还有空间嘛？', uid: 'a'),
];

void main() {
  group('portal comment grouping', () {
    test('quotes attach to the one earlier comment they start from', () {
      final index = ArticleCommentIndex.build(items);
      expect(index.roots.map((c) => c.cid), [14, 13, 10]);
      // 楼内按时间正序,便于顺着读
      expect(index.repliesFor(10).map((c) => c.cid), [11, 12, 15]);
      expect(index.replyToAuthor(11), isNull);
      expect(index.replyToAuthor(12), '读者乙');
      expect(index.replyToAuthor(15), '读者乙');
      expect(index.targetOf(14), isNull);
    });

    test('ambiguous or truncated quotes are handled conservatively', () {
      final twins = [
        comment(3, '丙', '再顶', quote: '甲: +1'),
        comment(2, '甲', '+1'),
        comment(1, '甲', '+1'),
      ];
      expect(ArticleCommentIndex.build(twins).targetOf(3), isNull);

      final cut = [
        comment(2, '乙', '同意', quote: '甲: 这是一段很长的评测意见...'),
        comment(1, '甲', '这是一段很长的评测意见，后面还有很多内容'),
      ];
      expect(ArticleCommentIndex.build(cut).targetOf(2)?.cid, 1);
    });

    test('shown roots stay roots when a later page reveals their target', () {
      final first = ArticleCommentIndex.build(items.take(2).toList());
      expect(first.roots.map((c) => c.cid), [15, 14]);
      final later = ArticleCommentIndex.build(
        items,
        pinnedRoots: first.roots.map((c) => c.cid).toSet(),
      );
      expect(later.roots.map((c) => c.cid), contains(15));
      expect(later.repliesFor(10).map((c) => c.cid), [11, 12]);
    });
  });

  test('article authors come from the publisher link and original author', () {
    final authors = parseArticleAuthors('''
<div class="bm vw"><div class="h hm">
  <h1 class="ph">评测</h1>
  <p class="xg1">2026-10-20 19:51<span class="pipe">|</span>
    发布者: <a href="space-uid-2.html">测试发布者</a>
    <span class="pipe">|</span>原作者: 测试原作者</p>
</div></div>''');
    expect(authors.uid, '2');
    expect(authors.names, {'测试发布者', '测试原作者'});
    expect(parseArticleAuthors('<div></div>').uid, isNull);
  });

  group('article comment sheet modes', () {
    Future<void> open(WidgetTester tester, {bool knowsAuthor = true}) async {
      tester.view.physicalSize = const Size(390, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => ArticleDiscussionPage.show(
                  context,
                  aid: 1,
                  title: '主板评测',
                  isLoggedIn: () => true,
                  loadPage: (_, _) async => ArticleDiscussion(
                    aid: 1,
                    title: '主板评测',
                    total: items.length,
                    page: const PageInfo(current: 1, hasNext: false),
                    items: items,
                    authorUid: knowsAuthor ? 'a' : null,
                  ),
                ),
                child: const Text('查看讨论'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('查看讨论'));
      await tester.pumpAndSettle();
    }

    Finder tile(int cid) => find.byKey(ValueKey('comment-$cid'));

    Future<void> pick(WidgetTester tester, String label) async {
      await tester.tap(
        find.descendant(
          of: find.byType(AppSegmented<CommentViewMode>),
          matching: find.text(label),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('comments group by quote and expand in place', (tester) async {
      await open(tester);
      expect(find.byType(CommentModeBar), findsOneWidget);
      expect(tile(10), findsOneWidget);
      expect(tile(11), findsNothing);
      // 认不出对象的引用保留引文
      expect(find.text('作者甲: 从没说过这句'), findsOneWidget);
      await tester.tap(find.text('展开 3 条回复'));
      await tester.pumpAndSettle();
      expect(tile(11), findsOneWidget);
      // 归组后不再重复引文;深层回复写明回复对象
      expect(find.text('作者甲: 第二卡还有空间嘛？'), findsNothing);
      expect(find.text('回复 读者乙：那第三槽呢'), findsOneWidget);
      expect(find.text('展开 3 条回复'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('floors keep source order and author mode filters to the '
        'article author', (tester) async {
      await open(tester);
      await pick(tester, '原楼层');
      final order = tester
          .widgetList<ArticleCommentTile>(find.byType(ArticleCommentTile))
          .map((t) => t.comment.cid)
          .toList();
      expect(order, [15, 14, 13, 12, 11, 10]);

      final header = tester.getTopLeft(find.byType(CommentModeBar)).dy;
      await pick(tester, '只看作者');
      // 控件固定在头部,切换不移动它
      expect(tester.getTopLeft(find.byType(CommentModeBar)).dy, header);
      final authorOnly = tester
          .widgetList<ArticleCommentTile>(find.byType(ArticleCommentTile))
          .toList();
      expect(authorOnly.map((t) => t.comment.cid), [15, 10]);
      expect(authorOnly.every((t) => t.byAuthor), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a switch after scrolling starts the new list at its top', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      // 两种方式下行高差别很大:沿用旧行偏移时滚动校正会停在中间
      final long = List.filled(6, '很长的评论内容用于拉开高度差异').join();
      final mixed = [
        for (var i = 40; i > 0; i--)
          i.isEven
              ? comment(i, '读者$i', '短评 $i', quote: '读者${i - 1}: $long ${i - 1}')
              : comment(i, '读者$i', '$long $i'),
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => ArticleDiscussionPage.show(
                  context,
                  aid: 1,
                  title: '主板评测',
                  isLoggedIn: () => true,
                  loadPage: (_, _) async => ArticleDiscussion(
                    aid: 1,
                    title: '主板评测',
                    page: const PageInfo(current: 1, hasNext: false),
                    items: mixed,
                  ),
                ),
                child: const Text('查看讨论'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('查看讨论'));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('discussion-sheet-grip')),
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
      final list = find
          .descendant(
            of: find.byType(ArticleDiscussionPage),
            matching: find.byType(Scrollable),
          )
          .first;
      for (var i = 0; i < 4; i++) {
        await tester.drag(list, const Offset(0, -500));
        await tester.pumpAndSettle();
      }
      expect(
        tester.state<ScrollableState>(list).position.pixels,
        greaterThan(0),
      );
      await pick(tester, '原楼层');
      expect(tester.state<ScrollableState>(list).position.pixels, 0);
      expect(
        tester
            .widgetList<ArticleCommentTile>(find.byType(ArticleCommentTile))
            .first
            .comment
            .cid,
        40,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('without a known author only two modes are offered', (
      tester,
    ) async {
      await open(tester, knowsAuthor: false);
      expect(find.text('原楼层'), findsOneWidget);
      expect(find.text('只看作者'), findsNothing);
    });
  });
}
