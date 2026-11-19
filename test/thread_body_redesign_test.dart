import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/widgets/avatar_image.dart';
import 'package:chh_app/widgets/rich_content_text.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/parser/thread_parser.dart';
import 'package:chh_app/widgets/post_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('thread header counts from synthetic HTML', () {
    test('parses separated markup, commas, zero and missing counters', () {
      final detail = parseThread(
        '''<div id="postlist"><table><tr>
        <td class="pls ptn pbn"><span>查看:</span><span class="xi1">8,047</span>
        <span>回复:</span><span class="xi1">47</span></td></tr></table></div>''',
        tid: 1,
      );
      expect(detail.viewCount, 8047);
      expect(detail.replyCount, 47);
      final zero = parseThread(
        '<div id="postlist"><div class="hm">回复：0</div></div>',
        tid: 1,
      );
      expect(zero.viewCount, isNull);
      expect(zero.replyCount, 0);
    });
    test('never derives totals from posts, titles, ratings or abbreviations', () {
      for (final html in [
        '<div id="postlist"><table id="pid42"><tr><td class="hm">查看: 100 回复: 9</td></tr></table></div>',
        '<div id="postlist"><h1 class="ts">查看: 100 回复: 9</h1></div>',
        '<div id="postlist"><div class="hm">查看: 1.2万 回复: 9k</div></div>',
        '<div class="hm">查看: 100 回复: 9</div>',
        '<div id="postlist"><div class="hm">查看: 8,04 回复: -1</div></div>',
      ]) {
        final detail = parseThread(html, tid: 1);
        expect(detail.viewCount, isNull);
        expect(detail.replyCount, isNull);
      }
    });
  });

  testWidgets(
    'editing badge requires a verified edit at least ten minutes later',
    (tester) async {
      for (final entry in <String, bool>{
        '12:09:59': false,
        '12:10:00': true,
        '12:11:00': true,
        '11:59:00': false,
      }.entries) {
        final post = Post(
          pid: 1,
          floor: 1,
          author: '样例作者',
          timeRaw: '2026-11-15 12:00:00',
          content: const [TextBlock('正文')],
          notes: [
            PostNote(
              PostNoteKind.edited,
              '本帖最后由 样例作者 于 2026-11-15 ${entry.key} 编辑',
            ),
          ],
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(Brightness.light),
            home: Scaffold(body: PostCard(post: post, isOpening: true)),
          ),
        );
        expect(
          find.textContaining('编辑'),
          entry.value ? findsOneWidget : findsNothing,
        );
      }
    },
  );

  testWidgets(
    'opening footer has no action pills and author more remains reachable',
    (tester) async {
      final actions = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: Scaffold(
            body: Column(
              children: [
                PostCard.header(
                  post: const Post(
                    pid: 1,
                    floor: 1,
                    author: '作者',
                    timeRaw: '',
                    content: [],
                  ),
                  isOpening: true,
                  onMore: () => actions.add('more'),
                ),
                const PostCard.footer(
                  post: Post(
                    pid: 1,
                    floor: 1,
                    author: '作者',
                    timeRaw: '',
                    content: [],
                  ),
                  isOpening: true,
                ),
              ],
            ),
          ),
        ),
      );
      for (final label in ['回复', '点评', '评分']) {
        expect(find.text(label), findsNothing);
      }
      await tester.tap(find.byKey(const ValueKey('post-more-1')));
      await tester.pumpAndSettle();
      expect(actions, ['more']);
    },
  );
  testWidgets('opening author and content align directly on the paper', (
    tester,
  ) async {
    const post = Post(
      pid: 1,
      floor: 1,
      author: '作者',
      timeRaw: '昨天 12:34',
      content: [TextBlock('正文')],
    );
    for (final split in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 390,
                child: split
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          PostCard.header(
                            post: post,
                            isOpening: true,
                            onMore: () {},
                          ),
                          const PostCard.block(
                            post: post,
                            isOpening: true,
                            contentBlock: TextBlock('正文'),
                          ),
                        ],
                      )
                    : PostCard(post: post, isOpening: true, onMore: () {}),
              ),
            ),
          ),
        ),
      );
      final avatar = find.byType(AvatarFrame);
      final name = find.text('作者');
      final time = find.text('昨天 12:34');
      final more = find.byKey(const ValueKey('post-more-1'));
      final surface = find.descendant(
        of: more,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).shape == BoxShape.circle,
        ),
      );
      expect(tester.getTopLeft(avatar).dx, 20);
      expect(tester.getSize(avatar), const Size.square(44));
      expect(tester.getTopLeft(time).dx, tester.getTopLeft(name).dx);
      expect(
        tester.getTopLeft(time).dy,
        greaterThan(tester.getBottomLeft(name).dy),
      );
      expect(tester.getSize(surface), const Size.square(36));
      expect(
        (tester.widget<DecoratedBox>(surface).decoration as BoxDecoration)
            .color,
        AppTokens.of(tester.element(more)).surface2,
      );
      expect(tester.getTopLeft(find.byType(RichContentText)).dx, 20);
      final body = tester.widget<RichContentText>(find.byType(RichContentText));
      expect(body.style!.fontSize, 17);
      expect(body.style!.height, 1.8);
    }
  });

  testWidgets('ratings align with the body and reserve the specified gaps', (
    tester,
  ) async {
    const body = TextBlock('正文');
    for (final opening in [true, false]) {
      final post = Post(
        pid: 1,
        floor: opening ? 1 : 2,
        author: '作者',
        timeRaw: '昨天 12:34',
        content: const [body],
        rating: const PostRating(
          summary: ['参与人数 1', '邪恶指数 +20'],
          entries: [RatingEntry(user: '评分者', score: '+20')],
        ),
      );
      for (final split in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(Brightness.light),
            home: Scaffold(
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (split) ...[
                    PostCard.block(
                      post: post,
                      isOpening: opening,
                      contentBlock: body,
                      contentIndex: 0,
                    ),
                    PostCard.footer(post: post, isOpening: opening),
                  ] else
                    PostCard(post: post, isOpening: opening),
                ],
              ),
            ),
          ),
        );
        final text = tester.getRect(find.byType(RichContentText));
        final strip = tester.getRect(
          find.byKey(const ValueKey('post-rating-strip')),
        );
        expect(strip.left, text.left);
        expect(strip.top - text.bottom, 8);
        expect(strip.height, 26);
        if (!opening) {
          final timeRow = tester.getRect(
            find
                .descendant(
                  of: find.byType(CommentMetaRow),
                  matching: find.byType(Row),
                )
                .first,
          );
          expect(timeRow.top - strip.bottom, 6);
        }
      }
    }
  });
}
