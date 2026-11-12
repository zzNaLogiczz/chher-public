import 'package:chh_app/design/theme.dart';
import 'package:chh_app/models/article_discussion.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/article_discussion_page.dart';
import 'package:chh_app/widgets/article_discussion_widgets.dart';
import 'package:chh_app/widgets/article_reply_sheet.dart';
import 'package:chh_app/widgets/comment_mode_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ArticleComment _long(int cid, {bool nested = false}) => ArticleComment(
  cid: cid,
  author: nested ? '合成回复者' : '合成作者',
  authorUid: '1',
  timeRaw: '2001-01-02 09:30',
  text: nested ? '长回复正文' : '主评论正文',
  content: [
    if (nested) const QuoteBlock([TextBlock('合成作者: 主评论正文')]),
    for (var i = 0; i < 1000; i++) TextBlock('合成段落$cid-$i'),
  ],
);

Future<void> _mount(
  WidgetTester tester,
  List<ArticleComment> items, {
  bool reduced = false,
  Future<PostResult> Function(String, ArticleComment?)? submit,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
        child: child!,
      ),
      home: ArticleDiscussionPage(
        aid: 1,
        title: '合成讨论',
        isLoggedIn: () => true,
        submitReply: submit,
        loadPage: (_, _) async => ArticleDiscussion(
          aid: 1,
          title: '合成讨论',
          authorUid: '1',
          items: items,
          page: const PageInfo(current: 1, hasNext: false),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectLazy() {
  expect(find.byType(DiscussionCommentBlock).evaluate().length, lessThan(80));
  expect(find.byType(CustomScrollView), findsOneWidget);
  expect(find.byType(ListView), findsNothing);
}

Future<void> _toEnd(WidgetTester tester) async {
  final scroll = tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position;
  for (var i = 0; i < 8; i++) {
    scroll.jumpTo(scroll.maxScrollExtent);
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets(
    'a 1000-block portal comment builds only visible sliver fragments',
    (tester) async {
      await _mount(tester, [_long(1)]);
      _expectLazy();
      expect(find.text('合成段落1-0'), findsOneWidget);
      expect(find.text('合成段落1-999'), findsNothing);
      expect(
        find.byKey(const ValueKey('article-comment-reply-1')),
        findsNothing,
      );
      // The author filter remains fixed while the body uses the same scrollable.
      final modes = tester.getRect(find.byType(CommentModeBar));
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -1200));
      await tester.pumpAndSettle();
      _expectLazy();
      expect(tester.getRect(find.byType(CommentModeBar)), modes);
      expect(find.text('合成段落1-0'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final reduced in [false, true]) {
    testWidgets('expanding ten long replies stays lazy reduced=$reduced', (
      tester,
    ) async {
      await _mount(tester, [
        const ArticleComment(cid: 1, author: '合成作者', text: '主评论正文'),
        for (var i = 2; i <= 13; i++) _long(i, nested: true),
      ], reduced: reduced);
      await tester.tap(find.byKey(const ValueKey('article-expand-replies-1')));
      await tester.pump();
      _expectLazy(); // Includes the zero-height first frame of the reveal.
      await tester.pump(const Duration(milliseconds: 16));
      _expectLazy();
      await tester.pumpAndSettle();
      _expectLazy();
      // The public tree remains lazy; only the first selected reply is nearby.
      expect(find.byKey(const ValueKey('comment-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('comment-12')), findsNothing);
      expect(find.byType(DiscussionQuote), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'long comment footer replies with its original CID and retains drafts',
    (tester) async {
      ArticleComment? target;
      await _mount(
        tester,
        [_long(1)],
        submit: (message, comment) async {
          target = comment;
          return const PostResult(PostResultKind.failed, '合成提交失败');
        },
      );
      await _toEnd(tester);
      final reply = find.byKey(const ValueKey('article-comment-reply-1'));
      expect(reply, findsOneWidget);
      await tester.ensureVisible(reply);
      await tester.tap(reply);
      await tester.pumpAndSettle();
      expect(find.byType(ArticleReplySheet), findsOneWidget);
      await tester.enterText(find.byType(TextField), '合成长评论回复草稿');
      await tester.pumpAndSettle();
      await tester.tap(find.text('发送'));
      await tester.pumpAndSettle();
      expect(target?.cid, 1);
      expect(find.text('合成提交失败'), findsOneWidget);
      Navigator.of(tester.element(find.byType(ArticleReplySheet))).pop();
      await tester.pumpAndSettle();
      await tester.tap(reply);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '合成长评论回复草稿',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
