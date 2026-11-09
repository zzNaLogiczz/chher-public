import 'package:chh_app/core/reading_prefs.dart';
import 'package:chh_app/design/reading.dart';
import 'package:chh_app/design/icons.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/design/typography.dart';
import 'package:chh_app/pages/thread_detail_page.dart';
import 'package:chh_app/ui/press.dart';
import 'package:chh_app/ui/hit_slop.dart';
import 'package:chh_app/widgets/composer_sheet.dart';
import 'package:chh_app/widgets/post_feedback.dart';
import 'package:chh_app/widgets/thread_comment_widgets.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/widgets/post_card.dart';
import 'package:chh_app/widgets/rich_content_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:chh_app/ui/nav_bar.dart';
import 'package:chh_app/ui/reading_bar.dart';
import 'package:flutter_test/flutter_test.dart';

import 'threaded_thread_page_test.dart' as fixture;

const sample = Post(
  pid: 2,
  floor: 2,
  author: '作者',
  timeRaw: '10-30 12:00',
  content: [TextBlock('一行评论')],
);

Future<void> mount(
  WidgetTester tester,
  Widget child, {
  ReadingPrefsController? controller,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      home: Scaffold(
        body: controller == null
            ? SingleChildScrollView(child: child)
            : ReadingScope(
                controller: controller,
                child: SingleChildScrollView(child: child),
              ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('whole and lazy replies follow content notes and feedback once', (
    tester,
  ) async {
    const post = Post(
      pid: 2,
      floor: 2,
      author: '作者',
      timeRaw: '今天',
      content: [TextBlock('正文')],
      notes: [PostNote(PostNoteKind.supplement, '追加内容')],
      comments: [PostComment(author: '点评者', text: '点评')],
    );
    for (final nested in [false, true]) {
      for (final split in [false, true]) {
        for (final enabled in [false, true]) {
          var replies = 0;
          final onReply = enabled ? () => replies++ : null;
          final header = PostCard.header(
            post: post,
            isOpening: false,
            commentStyle: true,
            nested: nested,
            onReply: onReply,
          );
          final footer = PostCard.footer(
            post: post,
            isOpening: false,
            commentStyle: true,
            nested: nested,
            onReply: onReply,
          );
          await mount(
            tester,
            split
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      header,
                      PostCard.block(
                        post: post,
                        isOpening: false,
                        commentStyle: true,
                        nested: nested,
                        contentBlock: post.content.single,
                      ),
                      footer,
                    ],
                  )
                : PostCard(
                    post: post,
                    isOpening: false,
                    commentStyle: true,
                    nested: nested,
                    onReply: onReply,
                  ),
          );
          final reply = find.byKey(const ValueKey('comment-reply-2'));
          if (split) {
            expect(
              find.descendant(of: find.byWidget(header), matching: reply),
              findsNothing,
            );
            expect(
              find.descendant(of: find.byWidget(footer), matching: reply),
              enabled ? findsOneWidget : findsNothing,
            );
          }
          expect(reply, enabled ? findsOneWidget : findsNothing);
          if (!enabled) continue;
          expect(find.text('回复'), findsOneWidget);
          expect(tester.getSemantics(reply).label, '回复');
          expect(find.byIcon(AppIcons.reply), findsNothing);
          final body = tester.getRect(find.byType(RichContentText).first);
          final note = tester.getRect(find.text('追加内容'));
          final feedback = tester.getRect(find.byType(CommentFeedback));
          final rect = tester.getRect(reply);
          final time = tester.getRect(find.text(post.timeRaw));
          expect(time.left, closeTo(body.left, .01));
          expect(rect.left - time.right, closeTo(8, .01));
          expect(rect.top, greaterThan(note.bottom));
          expect(rect.top - feedback.bottom, closeTo(8, .01));
          expect(rect.height, inInclusiveRange(20, 22));
          await tester.tap(reply);
          await tester.pumpAndSettle();
          expect(replies, 1);
        }
      }
    }
  });

  testWidgets(
    'single line comment with footer reply stays at most 104dp tall',
    (tester) async {
      await mount(
        tester,
        PostCard(
          post: sample,
          isOpening: false,
          commentStyle: true,
          onReply: () {},
        ),
      );
      expect(
        tester.getSize(find.byType(PostCard)).height,
        lessThanOrEqualTo(104),
      );
    },
  );

  testWidgets('reply accepts taps outside the 28 by 20 visual', (tester) async {
    var replies = 0;
    await mount(
      tester,
      PostCard(
        post: sample,
        isOpening: false,
        commentStyle: true,
        onReply: () => replies++,
      ),
    );
    final reply = find.byKey(const ValueKey('comment-reply-2'));
    final rect = tester.getRect(reply);
    expect(rect.size, const Size(28, 20));
    final target = tester.widget<HitSlopTarget>(
      find.ancestor(of: reply, matching: find.byType(HitSlopTarget)),
    );
    expect(rect.width + target.slop.horizontal, greaterThanOrEqualTo(44));
    expect(rect.height + target.slop.vertical, greaterThanOrEqualTo(44));
    await tester.tapAt(Offset(rect.center.dx, rect.bottom + 11));
    await tester.pumpAndSettle();
    expect(replies, 1);
    await tester.tapAt(Offset(rect.right + 7, rect.center.dy));
    await tester.pumpAndSettle();
    expect(replies, 2);
  });

  testWidgets('reading preferences update mounted comments', (tester) async {
    final controller = ReadingPrefsController(directory: () async => null);
    addTearDown(controller.dispose);
    await mount(
      tester,
      const PostCard(post: sample, isOpening: false, commentStyle: true),
      controller: controller,
    );
    final avatar = find.descendant(
      of: find.byKey(const ValueKey('post-avatar-2')),
      matching: find.byType(ClipRRect),
    );
    expect(tester.getSize(avatar), const Size(32, 32));
    await controller.set(
      const ReadingPrefs(
        layout: ReadingLayout.compact,
        fontSize: ReadingFontSize.xl,
        lineHeight: ReadingLineHeight.loose,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(avatar), const Size(28, 28));
    final body = tester.widget<RichContentText>(find.byType(RichContentText));
    expect(body.style!.fontSize, 19);
    expect(body.style!.height, closeTo(1.75, .001));
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening has no homepage, floor number or reply action', (
    tester,
  ) async {
    for (final card in [
      PostCard(post: sample, isOpening: true, onReply: () {}),
      PostCard.header(post: sample, isOpening: true, onReply: () {}),
      PostCard.footer(post: sample, isOpening: true, onReply: () {}),
    ]) {
      await mount(tester, card);
      expect(find.text('主页'), findsNothing);
      expect(find.text('#2'), findsNothing);
      expect(find.text('回复'), findsNothing);
      expect(find.bySemanticsLabel('回复'), findsNothing);
    }
    await mount(
      tester,
      PostCard(post: sample, isOpening: false, onReply: () {}),
    );
    expect(find.text('回复 #2'), findsOneWidget);
  });
  testWidgets('expanded reply target preserves drag scrolling', (tester) async {
    var replies = 0;
    await mount(
      tester,
      Column(
        children: [
          PostCard(
            post: sample,
            isOpening: false,
            commentStyle: true,
            onReply: () => replies++,
          ),
          const SizedBox(height: 1400),
        ],
      ),
    );
    final rect = tester.getRect(find.byKey(const ValueKey('comment-reply-2')));
    final gesture = await tester.startGesture(
      Offset(rect.center.dx, rect.bottom + 11),
    );
    await gesture.moveBy(const Offset(0, -30));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -60));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(replies, 0);
    expect(
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .pixels,
      greaterThan(0),
    );
  });

  testWidgets('visible adjacent content wins over reply hit margin', (
    tester,
  ) async {
    var replies = 0;
    var other = 0;
    var adjacentLeft = 62.0;
    Widget content() => Stack(
      children: [
        PostCard(
          post: sample,
          isOpening: false,
          commentStyle: true,
          onReply: () => replies++,
        ),
        Positioned(
          bottom: 0,
          left: adjacentLeft,
          child: PressScale(
            onTap: () => other++,
            child: const SizedBox(width: 28, height: 10, child: Text('邻接')),
          ),
        ),
      ],
    );
    await mount(tester, content());
    final rect = tester.getRect(find.byKey(const ValueKey('comment-reply-2')));
    adjacentLeft = rect.left;
    await mount(tester, content());
    await tester.tapAt(Offset(rect.center.dx, rect.bottom + 11));
    await tester.pumpAndSettle();
    expect(other, 1);
    expect(replies, 0);
  });

  testWidgets('floor reply stays lightweight and has expanded target', (
    tester,
  ) async {
    var replies = 0;
    await mount(
      tester,
      PostCard(post: sample, isOpening: false, onReply: () => replies++),
    );
    final control = find.ancestor(
      of: find.text('回复 #2'),
      matching: find.byType(PressScale),
    );
    final rect = tester.getRect(control);
    expect(rect.height, 20);
    await tester.tapAt(Offset(rect.center.dx, rect.bottom + 8));
    await tester.pumpAndSettle();
    expect(replies, 1);
  });

  testWidgets(
    'notes condense dates, preserve fallback and use amber supplement',
    (tester) async {
      const post = Post(
        pid: 1,
        floor: 1,
        author: '作者',
        timeRaw: '今天',
        content: [TextBlock('正文')],
        notes: [
          PostNote(PostNoteKind.edited, '本帖最后由 作者 于 2026-10-30 12:34 编辑'),
          PostNote(PostNoteKind.edited, '无法提取的编辑原文'),
          PostNote(PostNoteKind.supplement, '补充内容 (2026-10-31 08:20): 追加正文'),
        ],
      );
      await mount(tester, const PostCard(post: post, isOpening: true));
      expect(find.text('10-30 12:34 编辑过'), findsOneWidget);
      expect(find.text('无法提取的编辑原文'), findsOneWidget);
      expect(find.text('楼主补充 10-31'), findsOneWidget);
      expect(find.text('追加正文'), findsOneWidget);
      final panel = tester
          .widgetList<Container>(find.byType(Container))
          .where((w) => w.decoration is BoxDecoration)
          .map((w) => w.decoration! as BoxDecoration)
          .singleWhere((d) => d.color == AppTokens.light.warnBg);
      expect((panel.border! as Border).left.width, 3);
      expect((panel.border! as Border).left.color, AppTokens.light.warn);
    },
  );

  testWidgets('feedback starts six pixels below comment body', (tester) async {
    const post = Post(
      pid: 2,
      floor: 2,
      author: '作者',
      timeRaw: '今天',
      content: [TextBlock('正文')],
      comments: [PostComment(author: '点评者', text: '点评')],
    );
    await mount(
      tester,
      const PostCard(post: post, isOpening: false, commentStyle: true),
    );
    final body = tester.getRect(find.byType(RichContentText));
    final feedback = tester.getRect(find.byType(CommentFeedback));
    expect(feedback.top - body.bottom, 6);
  });

  testWidgets(
    'nested and lazy comments use reading avatars and footer metadata',
    (tester) async {
      final controller = ReadingPrefsController(directory: () async => null);
      addTearDown(controller.dispose);
      for (final split in [false, true]) {
        await controller.reset();
        await mount(
          tester,
          split
              ? Column(
                  children: [
                    PostCard.header(
                      post: sample,
                      isOpening: false,
                      commentStyle: true,
                      nested: true,
                      onReply: () {},
                    ),
                    const PostCard.block(
                      post: sample,
                      isOpening: false,
                      commentStyle: true,
                      nested: true,
                      contentBlock: TextBlock('正文'),
                    ),
                    PostCard.footer(
                      post: sample,
                      isOpening: false,
                      commentStyle: true,
                      nested: true,
                      onReply: () {},
                    ),
                  ],
                )
              : PostCard(
                  post: sample,
                  isOpening: false,
                  commentStyle: true,
                  nested: true,
                  onReply: () {},
                ),
          controller: controller,
        );
        final avatar = find.descendant(
          of: find.byKey(const ValueKey('post-avatar-2')),
          matching: find.byType(ClipRRect),
        );
        expect(tester.getSize(avatar), const Size(24, 24));
        expect(find.byKey(const ValueKey('comment-reply-2')), findsOneWidget);
        expect(find.text('#2'), findsNothing);
        double textBaseline(String text) {
          final paragraph = tester.renderObject<RenderParagraph>(
            find.descendant(
              of: find.text(text),
              matching: find.byType(RichText),
            ),
          );
          final painter = TextPainter(
            text: paragraph.text,
            textDirection: paragraph.textDirection,
            textScaler: paragraph.textScaler,
            strutStyle: paragraph.strutStyle,
            textHeightBehavior: paragraph.textHeightBehavior,
          )..layout(maxWidth: paragraph.size.width);
          final baseline = painter.computeLineMetrics().last.baseline;
          painter.dispose();
          return paragraph.localToGlobal(Offset(0, baseline)).dy;
        }

        expect(
          textBaseline('10-30 12:00') - textBaseline('回复'),
          closeTo(
            AppType.sizeFootnote * ReadingMetrics.commentReplyOpticalLiftEm,
            .01,
          ),
        );
        await controller.set(const ReadingPrefs(layout: ReadingLayout.compact));
        await tester.pumpAndSettle();
        expect(tester.getSize(avatar), const Size(22, 22));
      }
    },
  );

  testWidgets('thread title, opening body, gutter and band update together', (
    tester,
  ) async {
    final controller = ReadingPrefsController(directory: () async => null);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        home: ReadingScope(
          controller: controller,
          child: ThreadDetailPage(
            tid: 1,
            title: '布局标题',
            loadPage: (_, _, _) async => const ThreadDetail(
              tid: 1,
              title: '布局标题',
              forumName: '硬件',
              posts: [
                Post(
                  pid: 1,
                  floor: 1,
                  author: '楼主',
                  timeRaw: '今天',
                  content: [TextBlock('首楼正文')],
                ),
                sample,
              ],
              page: PageInfo(current: 1, hasNext: false),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Text title() => tester
        .widgetList<Text>(find.text('布局标题'))
        .singleWhere((text) => text.style?.letterSpacing == -.4);
    RichContentText body() => tester
        .widgetList<RichContentText>(find.byType(RichContentText))
        .singleWhere((w) => w.block.text == '首楼正文');
    final band = find.byWidgetPredicate(
      (w) => w is ColoredBox && w.color == AppTokens.dark.threadSectionBand,
    );
    expect(title().style!.fontSize, 24);
    expect(body().style!.fontSize, 17);
    expect(tester.getTopLeft(find.text('首楼正文')).dx, 20);
    expect(tester.getSize(band).height, 8);
    expect(find.byType(ThreadCommentHeading), findsOneWidget);
    await controller.set(
      const ReadingPrefs(
        layout: ReadingLayout.compact,
        fontSize: ReadingFontSize.xl,
        lineHeight: ReadingLineHeight.loose,
      ),
    );
    await tester.pumpAndSettle();
    expect(title().style!.fontSize, 22);
    expect(body().style!.fontSize, 20);
    expect(body().style!.height, 1.85);
    expect(tester.getTopLeft(find.text('首楼正文')).dx, 16);
    expect(tester.getSize(band).height, 6);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'nested hit regions prefer visible siblings before expanded targets',
    (tester) async {
      var visible = 0;
      var expanded = 0;
      await mount(
        tester,
        HitSlopRegion(
          child: SizedBox(
            height: 80,
            child: Stack(
              children: [
                Positioned(
                  top: 4,
                  left: 20,
                  child: PressScale(
                    onTap: () => visible++,
                    child: const SizedBox(
                      width: 28,
                      height: 10,
                      child: Text('可见'),
                    ),
                  ),
                ),
                Positioned(
                  top: 16,
                  left: 20,
                  child: HitSlopRegion(
                    child: HitSlopTarget(
                      enabled: true,
                      slop: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 12,
                      ),
                      child: PressScale(
                        onTap: () => expanded++,
                        child: const SizedBox(
                          width: 28,
                          height: 20,
                          child: Text('回复'),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      final rect = tester.getRect(find.text('回复'));
      await tester.tapAt(Offset(rect.center.dx, rect.top - 8));
      await tester.pumpAndSettle();
      expect(visible, 1);
      expect(expanded, 0);
      await tester.tapAt(Offset(rect.right + 7, rect.center.dy));
      await tester.pumpAndSettle();
      expect(expanded, 1);
    },
  );

  testWidgets('nested container has no guide and preserves reply hit margins', (
    tester,
  ) async {
    await fixture.pump(
      tester,
      ThreadDetailPage(
        tid: 123,
        title: '嵌套命中',
        loadPage: (_, _, _) async => fixture.page([
          fixture.post(1),
          fixture.post(2),
          fixture.post(3, target: 2),
        ]),
        submitReply:
            ({
              required tid,
              required fid,
              required message,
              quotePid,
              page = 1,
            }) async => const PostResult(PostResultKind.success, '成功'),
      ),
    );
    final expand = find.byKey(const ValueKey('thread-expand-replies-2'));
    await tester.ensureVisible(expand);
    await tester.tap(expand);
    await tester.pumpAndSettle();
    final reply = find.byKey(const ValueKey('comment-reply-3'));
    await tester.ensureVisible(reply);
    await tester.pumpAndSettle();
    final guides = tester
        .widgetList<Container>(
          find.ancestor(of: reply, matching: find.byType(Container)),
        )
        .where((container) {
          final decoration = container.decoration;
          return decoration is BoxDecoration &&
              decoration.border is Border &&
              (decoration.border! as Border).left.width == 2;
        });
    expect(guides, isEmpty);
    final rect = tester.getRect(reply);
    // The adjacent more action now owns the shared horizontal margin.
    // Verify reply's expanded touch area above its visible bounds instead.
    await tester.tapAt(Offset(rect.center.dx, rect.top - 8));
    await tester.pumpAndSettle();
    expect(find.byType(ComposerSheet), findsOneWidget);
  });
  testWidgets(
    'system scaling caps xl reading body at 26 without scaling chrome',
    (tester) async {
      final controller = ReadingPrefsController(directory: () async => null);
      addTearDown(controller.dispose);
      await controller.set(const ReadingPrefs(fontSize: ReadingFontSize.xl));
      const opening = Post(
        pid: 1,
        floor: 1,
        author: '楼主',
        timeRaw: '',
        content: [
          TextBlock('字号上限正文', nodes: [InlineText('字号上限正文')]),
        ],
      );
      const reply = Post(
        pid: 2,
        floor: 2,
        author: '评论者',
        timeRaw: '',
        content: [
          TextBlock('字号上限评论', nodes: [InlineText('字号上限评论')]),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: ReadingScope(
              controller: controller,
              child: ThreadDetailPage(
                tid: 1,
                title: '字号上限标题',
                loadPage: (_, _, _) async => const ThreadDetail(
                  tid: 1,
                  title: '字号上限标题',
                  posts: [opening, reply],
                  page: PageInfo(current: 1, hasNext: false),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      RenderParagraph paragraph(String text) =>
          tester.renderObject<RenderParagraph>(
            find.byWidgetPredicate(
              (w) => w is RichText && w.text.toPlainText() == text,
            ),
          );
      final body = paragraph('字号上限正文');
      expect(body.text.style!.fontSize, 20);
      expect(
        body.textScaler.scale(body.text.style!.fontSize!),
        lessThanOrEqualTo(26),
      );
      final comment = paragraph('字号上限评论');
      expect(
        comment.textScaler.scale(comment.text.style!.fontSize!),
        lessThanOrEqualTo(26),
      );
      final heading = find.byWidgetPredicate(
        (w) => w is Text && w.data == '字号上限标题' && w.style?.letterSpacing == -.4,
      );
      expect(
        MediaQuery.textScalerOf(tester.element(heading)).scale(20),
        closeTo(26, .001),
      );
      for (final chrome in [find.byType(NavOverlay), find.byType(ReadingBar)]) {
        expect(MediaQuery.textScalerOf(tester.element(chrome)).scale(20), 40);
      }
      // The inherited reading scale must also update when preferences change.
      await controller.set(const ReadingPrefs(fontSize: ReadingFontSize.m));
      await tester.pumpAndSettle();
      final updated = paragraph('字号上限正文');
      expect(updated.text.style!.fontSize, 17);
      expect(updated.textScaler.scale(17), closeTo(26, .001));
      expect(tester.takeException(), isNull);
    },
  );

  for (final layout in ReadingLayout.values) {
    for (final style in ['opening', 'floor', 'comment']) {
      testWidgets(
        '$style paragraphs have identical whole and split gaps in ${layout.name}',
        (tester) async {
          final controller = ReadingPrefsController(
            directory: () async => null,
          );
          addTearDown(controller.dispose);
          await controller.set(ReadingPrefs(layout: layout));
          final metrics = ReadingMetrics.fromPrefs(controller.prefs);
          final opening = style == 'opening';
          final comment = style == 'comment';
          const first = TextBlock('第一段正文');
          const second = TextBlock('第二段正文');
          const post = Post(
            pid: 1,
            floor: 1,
            author: '作者',
            timeRaw: '今天',
            content: [first, second],
          );
          final gaps = <double>[];
          for (final split in [false, true]) {
            await mount(
              tester,
              split
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        PostCard.header(
                          post: post,
                          isOpening: opening,
                          commentStyle: comment,
                        ),
                        PostCard.block(
                          post: post,
                          isOpening: opening,
                          commentStyle: comment,
                          contentBlock: first,
                        ),
                        PostCard.block(
                          post: post,
                          isOpening: opening,
                          commentStyle: comment,
                          contentBlock: second,
                          paragraphGapBefore: true,
                        ),
                        PostCard.footer(
                          post: post,
                          isOpening: opening,
                          commentStyle: comment,
                        ),
                      ],
                    )
                  : PostCard(
                      post: post,
                      isOpening: opening,
                      commentStyle: comment,
                    ),
              controller: controller,
            );
            Rect rect(TextBlock block) => tester.getRect(
              find.byWidgetPredicate(
                (w) => w is RichContentText && w.block.text == block.text,
              ),
            );
            gaps.add(rect(second).top - rect(first).bottom);
            expect(
              gaps.last,
              closeTo(metrics.paragraphGap, .001),
              reason: 'split=$split',
            );
          }
          expect(gaps[1], closeTo(gaps[0], .001));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
