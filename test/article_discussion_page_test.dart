import 'dart:async';

import 'package:chh_app/design/theme.dart';
import 'package:chh_app/models/article_discussion.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/article_discussion_page.dart';
import 'package:chh_app/widgets/article_reply_sheet.dart';
import 'package:chh_app/ui/app_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) =>
    MaterialApp(theme: buildAppTheme(Brightness.light), home: child);

ArticleDiscussion _empty() => const ArticleDiscussion(
  aid: 50001,
  title: '主板评测',
  items: [],
  page: PageInfo(current: 1, hasNext: false),
  total: 0,
);

void main() {
  testWidgets('failed comment load can retry without leaving the discussion', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      _app(
        ArticleDiscussionPage(
          aid: 50001,
          title: '主板评测',
          isLoggedIn: () => false,
          loadPage: (page, refresh) async {
            attempts++;
            if (attempts == 1) throw Exception('offline');
            return _empty();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('加载失败'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('暂时没有评论，写下你的看法'), findsOneWidget);
  });

  testWidgets('empty discussion routes a signed-out reply to login', (
    tester,
  ) async {
    var logins = 0;
    await tester.pumpWidget(
      _app(
        ArticleDiscussionPage(
          aid: 50001,
          title: '主板评测',
          isLoggedIn: () => false,
          onLogin: (_) async {
            logins++;
          },
          loadPage: (_, _) async => _empty(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('暂时没有评论，写下你的看法'), findsOneWidget);
    await tester.tap(find.text('登录后参与讨论'));
    await tester.pumpAndSettle();
    expect(logins, 1);
    expect(find.byType(ArticleReplySheet), findsNothing);
  });

  testWidgets(
    'comment pagination appends automatically and deduplicates cids',
    (tester) async {
      final requested = <int>[];
      await tester.pumpWidget(
        _app(
          ArticleDiscussionPage(
            aid: 50001,
            title: '主板评测',
            isLoggedIn: () => false,
            loadPage: (page, refresh) async {
              requested.add(page);
              return ArticleDiscussion(
                aid: 50001,
                title: '主板评测',
                items: page == 1
                    ? const [
                        ArticleComment(cid: 1, author: '读者甲', text: '第一条评论'),
                      ]
                    : const [
                        ArticleComment(cid: 1, author: '读者甲', text: '第一条评论'),
                        ArticleComment(cid: 2, author: '读者乙', text: '第二条评论'),
                      ],
                page: PageInfo(current: page, hasNext: page == 1),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(requested, [1, 2]);
      expect(find.text('第一条评论'), findsOneWidget);
      expect(find.text('第二条评论'), findsOneWidget);
    },
  );

  testWidgets('reply failure keeps text and context open for editing', (
    tester,
  ) async {
    var submissions = 0;
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => ArticleReplySheet.show(
                context,
                quoteAuthor: '读者甲',
                quoteText: '原评论的上下文',
                onSubmit: (_) async {
                  submissions++;
                  return const PostResult(PostResultKind.failed, '网络暂不可用');
                },
              ),
              child: const Text('打开回复'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开回复'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '我的回复草稿');
    await tester.pump();
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    expect(submissions, 1);
    expect(find.text('网络暂不可用'), findsOneWidget);
    expect(find.text('原评论的上下文'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '我的回复草稿',
    );
    expect(find.byType(ArticleReplySheet), findsOneWidget);
  });

  testWidgets('a pending reply cannot be sent a second time', (tester) async {
    final pending = Completer<PostResult>();
    var submissions = 0;
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: ArticleReplySheet(
            initialText: '测试草稿',
            onSubmit: (_) {
              submissions++;
              return pending.future;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('发送'));
    await tester.pump();
    await tester.tap(find.text('发送中'));
    await tester.pump();
    expect(submissions, 1);
    pending.complete(const PostResult(PostResultKind.failed, '请稍后重试'));
    await tester.pumpAndSettle();
    expect(find.text('测试草稿'), findsOneWidget);
  });

  testWidgets(
    'forum-only source shows the real thread entry instead of portal composition',
    (tester) async {
      await tester.pumpWidget(
        _app(
          ArticleDiscussionPage(
            aid: 50002,
            title: '桌面分享',
            isLoggedIn: () => false,
            loadPage: (_, _) async => const ArticleDiscussion(
              aid: 50002,
              title: '桌面分享',
              items: [],
              forumOnly: true,
              threadId: 900002,
              forumId: 319,
              page: PageInfo(current: 1, hasNext: false),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('原帖讨论'), findsOneWidget);
      expect(find.text('进入原帖回复'), findsOneWidget);
      expect(find.text('文章评论'), findsNothing);
      expect(find.text('写评论…'), findsNothing);
    },
  );

  testWidgets(
    'uncertain reply preserves the draft and requires checking comments before another send',
    (tester) async {
      var submissions = 0;
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: ArticleReplySheet(
              initialText: '需要确认结果的草稿',
              onSubmit: (_) async {
                submissions++;
                return const PostResult(PostResultKind.unknown, '未知');
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('发送'));
      await tester.pumpAndSettle();
      expect(submissions, 1);
      expect(find.text('返回评论确认'), findsOneWidget);
      expect(
        tester
            .widget<AppButton>(find.byKey(const ValueKey('composer-send')))
            .onPressed,
        isNull,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '需要确认结果的草稿',
      );
    },
  );
}
