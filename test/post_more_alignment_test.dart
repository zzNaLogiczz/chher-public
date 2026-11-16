import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/widgets/rich_content_text.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/ui/hit_slop.dart';
import 'package:chh_app/widgets/post_card.dart';
import 'package:chh_app/widgets/comment_row_interaction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('fine more dots align and fit dark=$dark scale=$scale', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var more = 0, reply = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(dark ? Brightness.dark : Brightness.light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: Scaffold(
              body: HitSlopRegion(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      PostCard.header(
                        post: Post(
                          pid: 7,
                          floor: 1,
                          author: '超长昵称测试用户Alpha非常长的名字',
                          timeRaw: '2026-11-04',
                          content: const [],
                        ),
                        isOpening: true,
                        onMore: () => more++,
                      ),
                      CommentMetaRow(
                        timeLabel: '昨天',
                        onReply: () => reply++,
                        onMore: () => more++,
                        moreKey: const ValueKey('more'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('…'), findsNothing);
        final icons = find.byType(SolidMoreIcon);
        expect(icons, findsOneWidget);
        expect(find.byType(CommentMoreButton), findsOneWidget);
        final opening = tester.getRect(
          find.byKey(const ValueKey('post-more-7')),
        );
        final author = tester.getRect(
          find.byKey(const ValueKey('post-profile-7')),
        );
        expect(opening.size, const Size(44, 44));
        expect(opening.center.dy, closeTo(author.center.dy, .01));
        expect(tester.getSize(icons.first), const Size(18, 18));
        final compact = tester.getRect(find.byKey(const ValueKey('more')));
        expect(compact.size, const Size(34, 28));
        expect(compact.right, closeTo(306, .01));
        final dots = find.descendant(
          of: find.byType(CommentMoreButton),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is DecoratedBox &&
                widget.decoration is BoxDecoration &&
                (widget.decoration as BoxDecoration).shape == BoxShape.circle,
          ),
        );
        expect(dots, findsNWidgets(3));
        for (final dot in dots.evaluate()) {
          expect((dot.renderObject as RenderBox).size, const Size(3, 3));
        }
        final replyRect = tester.getRect(find.text('回复'));
        expect(compact.center.dy, closeTo(replyRect.center.dy, 2));
        for (final point in [
          Offset(compact.left + 1, compact.center.dy),
          Offset(compact.right - 1, compact.center.dy),
          Offset(compact.center.dx, compact.top + 1),
          Offset(compact.center.dx, compact.bottom - 1),
        ]) {
          await tester.tapAt(point);
          await tester.pumpAndSettle();
        }
        expect(more, 4);
        await tester.tap(find.text('回复'));
        await tester.pumpAndSettle();
        expect(reply, 1);
        expect(more, 4);
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final mode in ['ordinary', 'floors', 'nested']) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('more stays at column edge $mode scale=$scale', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var more = 0;
        var replies = 0;
        const timestamp = '11-16 12:34';
        final post = Post(
          pid: 8,
          floor: 12,
          author: '合成作者',
          timeRaw: timestamp,
          content: const [TextBlock('合成正文')],
        );
        for (final style in AppearanceStyle.values) {
          for (final brightness in Brightness.values) {
            for (final lazy in [false, true]) {
              await tester.pumpWidget(
                MaterialApp(
                  theme: buildAppTheme(brightness, style),
                  home: MediaQuery(
                    data: MediaQueryData(
                      textScaler: TextScaler.linear(scale),
                      disableAnimations: true,
                    ),
                    child: Scaffold(
                      body: Padding(
                        padding: EdgeInsets.fromLTRB(
                          mode == 'nested' ? 60 : 16,
                          20,
                          16,
                          20,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final card in [
                              if (lazy) ...[
                                PostCard.block(
                                  post: post,
                                  isOpening: false,
                                  commentStyle: mode != 'floors',
                                  nested: mode == 'nested',
                                  contentBlock: post.content.single,
                                ),
                                PostCard.footer(
                                  post: post,
                                  isOpening: false,
                                  commentStyle: mode != 'floors',
                                  nested: mode == 'nested',
                                  onMore: () => more++,
                                  onReply: () => replies++,
                                ),
                              ] else
                                PostCard(
                                  post: post,
                                  isOpening: false,
                                  commentStyle: mode != 'floors',
                                  nested: mode == 'nested',
                                  onMore: () => more++,
                                  onReply: () => replies++,
                                ),
                            ])
                              Padding(
                                padding: EdgeInsets.only(
                                  right: mode == 'nested' ? 8 : 0,
                                ),
                                child: card,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              final meta = tester.getRect(find.byType(CommentMetaRow));
              final body = tester.getRect(find.byType(RichContentText));
              final menu = tester.getRect(find.byType(CommentMoreButton));
              final reply = tester.getRect(
                find.byKey(const ValueKey('comment-reply-8')),
              );
              final time = tester.getRect(find.text(timestamp));
              expect(
                meta.right,
                closeTo(
                  body.left +
                      tester
                          .renderObject<RenderBox>(find.byType(RichContentText))
                          .constraints
                          .maxWidth,
                  .01,
                ),
              );
              expect(menu.right, closeTo(meta.right + 6, .01));
              expect(menu.size, const Size(34, 28));
              expect(menu.center.dy, closeTo(reply.center.dy, .01));
              expect(menu.left, greaterThan(reply.right));
              if (scale == 2) {
                expect(time.bottom, lessThan(reply.top));
                expect(reply.left, closeTo(meta.left, .01));
              } else {
                expect(reply.left - time.right, closeTo(16, .01));
              }
              if (mode == 'floors') {
                final floor = tester.getRect(find.text('#12'));
                if (scale == 1) {
                  expect(floor.right + 16, closeTo(time.left, .01));
                  expect(floor.center.dy, closeTo(time.center.dy, .01));
                } else {
                  expect(floor.top, lessThanOrEqualTo(time.top));
                }
              } else {
                expect(find.text('#12'), findsNothing);
              }
              final previousMore = more;
              final previousReplies = replies;
              await tester.tapAt(menu.centerRight - const Offset(1, 0));
              await tester.pumpAndSettle();
              expect(more, previousMore + 1);
              expect(replies, previousReplies);
              await tester.tapAt(time.center);
              await tester.pumpAndSettle();
              expect(more, previousMore + 1);
              expect(replies, previousReplies);
              await tester.tap(find.text('回复'));
              await tester.pumpAndSettle();
              expect(replies, previousReplies + 1);
              expect(tester.takeException(), isNull);
            }
          }
        }
      });
    }
  }
}
