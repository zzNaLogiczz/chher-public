import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/thread_tokens.dart';
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
  testWidgets(
    'opening author and content keep their distinct 16 and 20 insets',
    (tester) async {
      const post = Post(
        pid: 1,
        floor: 1,
        author: '作者',
        timeRaw: '',
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
                      ? const Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            PostCard.header(post: post, isOpening: true),
                            PostCard.block(
                              post: post,
                              isOpening: true,
                              contentBlock: TextBlock('正文'),
                            ),
                          ],
                        )
                      : const PostCard(post: post, isOpening: true),
                ),
              ),
            ),
          ),
        );
        final authorCard = find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration! as BoxDecoration).borderRadius ==
                  BorderRadius.circular(ThreadTokens.authorRadius),
        );
        expect(tester.getTopLeft(authorCard).dx, 16);
        expect(tester.getSize(authorCard).width, 358);
        expect(tester.getTopLeft(find.byType(RichContentText)).dx, 20);
        final body = tester.widget<RichContentText>(
          find.byType(RichContentText),
        );
        expect(body.style!.fontSize, 17);
        expect(body.style!.height, 1.8);
      }
    },
  );
}
