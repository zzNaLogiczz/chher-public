import 'package:chh_app/core/display_time.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/models/image_stack_group.dart';
import 'package:chh_app/core/link_target.dart';
import 'package:chh_app/widgets/post_card.dart';
import 'package:chh_app/widgets/post_feedback.dart';
import 'package:chh_app/widgets/reading_list_end.dart';
import 'package:chh_app/widgets/chhers_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Post post({
  List<ContentBlock> content = const [],
  PostLock? lock,
  List<PostNote> notes = const [],
}) => Post(
  pid: 1,
  floor: 2,
  author: '合成作者',
  timeRaw: '2026-11-15 12:00',
  content: content,
  lock: lock,
  notes: notes,
);

Future<void> mount(
  WidgetTester tester,
  Widget child, {
  AppearanceStyle style = AppearanceStyle.cinnabar,
  Brightness brightness = Brightness.light,
}) => tester.pumpWidget(
  MaterialApp(
    theme: buildAppTheme(brightness, style),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

void main() {
  test(
    'only adjacent site links group, retaining source and gallery indices',
    () {
      final a = SiteLinkBlock(
        ThreadLink(
          Uri.parse('https://www.chiphell.com/thread-12-1-1.html'),
          tid: 12,
        ),
      );
      final b = SiteLinkBlock(
        ArticleLink(
          Uri.parse('https://www.chiphell.com/article-34-1.html'),
          aid: 34,
        ),
      );
      final blocks = <ContentBlock>[
        a,
        b,
        TextBlock('边界'),
        a,
        QuoteBlock([]),
        b,
        ImageBlock('a'),
        ImageBlock('b'),
        a,
        b,
      ];
      final segments = groupPostImages(blocks);
      expect(segments.map((s) => s.siteLinks?.length), [
        2,
        null,
        1,
        null,
        1,
        null,
        2,
      ]);
      expect(segments.last.blockIndex, 8);
      expect(segments.last.galleryIndex, 2);
      expect(segments[5].imageStack!.urls, ['a', 'b']);
      final article = groupPostImages(blocks, groupImages: false);
      expect(article.where((s) => s.imageStack != null), isEmpty);
      expect(
        article.where((s) => s.block is ImageBlock).map((s) => s.galleryIndex),
        [0, 1],
      );
    },
  );

  for (final style in AppearanceStyle.values) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'password and suppression keep actions in $style $brightness',
        (tester) async {
          var unlocks = 0;
          var replies = 0;
          await mount(
            tester,
            PostCard(
              post: post(
                lock: const PostLock(text: '请输入密码', needsPassword: true),
              ),
              isOpening: false,
              onUnlock: () => unlocks++,
              onReply: () => replies++,
            ),
            style: style,
            brightness: brightness,
          );
          expect(find.text('这段内容需要密码'), findsOneWidget);
          await tester.tap(find.text('输入密码'));
          await tester.pumpAndSettle();
          expect(unlocks, 1);
          await mount(
            tester,
            PostCard(
              post: post(
                content: const [
                  QuoteBlock([TextBlock('作者被禁止或删除 内容自动屏蔽')], isNotice: true),
                ],
              ),
              isOpening: false,
              onReply: () => replies++,
            ),
            style: style,
            brightness: brightness,
          );
          expect(find.text('作者被禁止或删除，内容已自动屏蔽'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('suppressed-avatar-1')),
            findsOneWidget,
          );
          expect(
            find.text(formatDisplayTime(raw: '2026-11-15 12:00')),
            findsOneWidget,
          );
          await tester.tap(find.text('回复'));
          await tester.pumpAndSettle();
          expect(replies, 1);
          expect(tester.binding.transientCallbackCount, 0);
        },
      );
    }
  }
  testWidgets('edit follows body and supplement stays literal', (tester) async {
    final p = post(
      content: const [TextBlock('原文')],
      notes: const [
        PostNote(PostNoteKind.edited, '本帖最后由 合成作者 于 2026-11-15 12:10 编辑'),
        PostNote(
          PostNoteKind.supplement,
          '补充内容 (2026-11-15 13:00): **原样文字**\n第二行',
        ),
      ],
    );
    await mount(tester, PostCard(post: p, isOpening: true));
    expect(find.text('**原样文字**\n第二行'), findsOneWidget);
    expect(
      tester
          .getTopLeft(
            find.text('最后编辑于 ${formatDisplayTime(raw: '2026-11-15 12:10')}'),
          )
          .dy,
      greaterThan(tester.getTopLeft(find.text('原文')).dy),
    );
    await mount(
      tester,
      Column(
        children: [
          PostCard.header(post: p, isOpening: true),
          PostCard.footer(post: p, isOpening: true),
        ],
      ),
    );
    expect(
      find.text('最后编辑于 ${formatDisplayTime(raw: '2026-11-15 12:10')}'),
      findsOneWidget,
    );
  });
  testWidgets('rating omits invented reasons and reading end stops ticking', (
    tester,
  ) async {
    await mount(
      tester,
      const Column(
        children: [
          OpeningFeedback(
            rating: PostRating(
              summary: ['积分 +1'],
              entries: [RatingEntry(user: '合成评分者', score: '+1')],
            ),
          ),
          ReadingListEnd(),
        ],
      ),
    );
    expect(
      find.text('—'),
      findsNWidgets(2),
      reason: 'Only the reading boundary has dashes.',
    );
    expect(find.text('已读到这里'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
    await mount(tester, const ReadingListEnd(loading: true));
    expect(find.text('正在加载'), findsNothing);
    expect(find.byType(ChhersLoader), findsOneWidget);
    await mount(tester, const ReadingListEnd());
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
  });
}
