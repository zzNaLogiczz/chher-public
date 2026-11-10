import 'package:chh_app/design/theme.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/parser/thread_parser.dart';
import 'package:chh_app/widgets/post_card.dart';
import 'package:chh_app/widgets/post_feedback.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/design/motion.dart';
import 'package:chh_app/ui/press.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

PostRating rating(
  int count, {
  int? participants,
  String? reason,
  bool negative = false,
}) => PostRating(
  summary: ['参与人数 ${participants ?? count}', '邪恶指数 +55'],
  entries: List.generate(
    count,
    (i) => RatingEntry(
      user: '评分者$i',
      score: negative && i == 0 ? '-5' : '+5',
      reason: reason,
    ),
  ),
);
List<PostComment> comments(int count) => List.generate(
  count,
  (i) => PostComment(author: '点评者$i', text: '点评正文$i', timeRaw: '10-24 12:00'),
);
Future<void> mount(
  WidgetTester tester,
  Widget child, {
  bool reduced = false,
  Brightness brightness = Brightness.light,
  double width = 390,
  double scale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(brightness),
      home: MediaQuery(
        data: MediaQueryData(
          disableAnimations: reduced,
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: width, child: child),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'common rating headers keep values and labels inline and compact',
    (tester) async {
      for (final opening in [true, false]) {
        await mount(
          tester,
          opening
              ? OpeningFeedback(rating: rating(4))
              : FloorFeedback(rating: rating(4)),
          width: 320,
        );
        final score = find.text('+55 邪恶指数');
        final people = find.text('4 人评分');
        expect(score, findsOneWidget);
        expect(people, findsOneWidget);
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: score, matching: find.byType(RichText)),
        );
        final number = paragraph.getBoxesForSelection(
          const TextSelection(baseOffset: 0, extentOffset: 3),
        );
        final label = paragraph.getBoxesForSelection(
          const TextSelection(baseOffset: 4, extentOffset: 8),
        );
        expect(number.single.bottom, closeTo(label.single.bottom, 3));
        final wrap = find
            .ancestor(of: score, matching: find.byType(Wrap))
            .first;
        final header = find
            .ancestor(of: wrap, matching: find.byType(Padding))
            .first;
        expect(
          tester.getSize(header).height,
          lessThanOrEqualTo(opening ? 44 : 38),
        );
        expect(
          tester.getTopLeft(people).dy,
          closeTo(tester.getTopLeft(score).dy, 1),
        );
        final avatars = find.descendant(of: wrap, matching: find.byType(Stack));
        expect(tester.getSize(avatars).height, opening ? 20 : 18);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('summary value styles preserve signed colors in both themes', (
    tester,
  ) async {
    const value = PostRating(
      summary: ['参与人数 4', '邪恶指数 +55', '家园分 -2'],
      entries: [],
    );
    for (final brightness in Brightness.values) {
      for (final opening in [true, false]) {
        await mount(
          tester,
          opening
              ? const OpeningFeedback(rating: value)
              : const FloorFeedback(rating: value),
          brightness: brightness,
        );
        final tokens = brightness == Brightness.light
            ? AppTokens.light
            : AppTokens.dark;
        for (final text in ['+55 邪恶指数', '-2 家园分', '4 人评分']) {
          final group = tester.widget<Text>(find.text(text));
          final span = group.textSpan! as TextSpan;
          final number = span.children!.first as TextSpan;
          final label = span.children!.last as TextSpan;
          expect(number.style!.fontSize, opening ? 15 : 14);
          expect(number.style!.fontWeight, FontWeight.w600);
          expect(
            number.style!.color,
            text.startsWith('-') ? tokens.red : tokens.green,
          );
          expect(label.style!.fontSize, opening ? 13 : 12);
          expect(group.maxLines, isNull);
        }
      }
    }
  });

  testWidgets('rating headers wrap safely in narrow columns and large text', (
    tester,
  ) async {
    final raw = List.filled(16, '超长原始标签').join();
    for (final width in [320.0, 180.0]) {
      for (final scale in [1.0, 2.0]) {
        for (final opening in [true, false]) {
          for (final value in [
            rating(4, participants: 12),
            PostRating(
              summary: ['参与人数 12', '邪恶指数 +55', '家园分 -2', raw],
              entries: const [],
            ),
          ]) {
            await mount(
              tester,
              opening
                  ? OpeningFeedback(rating: value)
                  : FloorFeedback(rating: value),
              width: width,
              scale: scale,
            );
            expect(find.text('+55 邪恶指数'), findsOneWidget);
            expect(find.text('12 人评分'), findsOneWidget);
            if (value.entries.isEmpty) {
              expect(find.text(raw), findsOneWidget);
              final label = tester.widget<Text>(find.text(raw));
              expect(label.maxLines, isNull);
              expect(label.overflow, isNot(TextOverflow.ellipsis));
              final rect = tester.getRect(find.text(raw));
              expect(rect.left, greaterThanOrEqualTo(0));
              expect(rect.right, lessThanOrEqualTo(width));
            } else {
              expect(find.text('+8'), findsOneWidget);
              expect(find.text('评分者1'), findsOneWidget);
            }
            expect(
              tester.takeException(),
              isNull,
              reason: 'opening=$opening width=$width scale=$scale',
            );
          }
        }
      }
    }
  });

  for (final rawSummary in [false, true]) {
    for (final score in ['+5', '-5']) {
      testWidgets(
        'missing usable summary (${rawSummary ? 'raw' : 'empty'}, $score) keeps known detail accessible',
        (tester) async {
          final parsed = parseThread('''
<table id="pid2"><tr><td><div class="authi"><strong><a href="space-uid-2.html">合成楼层作者</a></strong></div></td><td id="postmessage_2">合成正文</td></tr></table>
<dl id="ratelog_2"><table class="ratl"><tbody class="ratl_l"><tr><td><a href="space-uid-3.html">合成评分人</a></td><td>$score</td><td></td></tr></tbody></table></dl>
''', tid: 1).posts.single.rating!;
          expect(parsed.summary, isEmpty);
          final value = rawSummary
              ? PostRating(summary: const ['站点原文'], entries: parsed.entries)
              : parsed;
          expect(value.participants, isNull);
          expect(value.entries.single.user, '合成评分人');
          expect(value.entries.single.score, score);
          expect(value.entries.single.reason ?? '', isEmpty);
          for (final brightness in Brightness.values) {
            await mount(
              tester,
              CommentFeedback(rating: value),
              brightness: brightness,
            );
            final label = find.text(rawSummary ? '站点原文' : '评分');
            expect(label, findsOneWidget);
            expect(find.text('合成评分人'), findsNothing);
            await tap(tester, label);
            expect(find.text('合成评分人'), findsOneWidget);
            expect(find.text(score), findsOneWidget);
            if (score.startsWith('-')) {
              expect(
                tester.widget<Text>(find.text(score)).style!.color,
                brightness == Brightness.light
                    ? AppTokens.light.red
                    : AppTokens.dark.red,
              );
            }
            expect(find.textContaining('1人'), findsNothing);
            expect(find.textContaining('人评分'), findsNothing);
            expect(value.participants, isNull);
            await tap(tester, label);
            expect(find.text('合成评分人'), findsNothing);
          }
        },
      );
    }
  }

  test('green line tokens preserve both themes and copyWith overrides', () {
    for (final tokens in [AppTokens.light, AppTokens.dark]) {
      expect(tokens.copyWith().greenLine, tokens.greenLine);
      expect(tokens.copyWith(greenLine: tokens.red).greenLine, tokens.red);
    }
  });
  testWidgets('wrapped capsule rows keep six pixels between visual bounds', (
    tester,
  ) async {
    await mount(
      tester,
      CommentFeedback(rating: rating(4), comments: comments(2)),
      width: 240,
    );
    final controls = find.byType(PressScale);
    final first = tester.getRect(controls.first);
    final second = tester.getRect(controls.at(1));
    expect(first.height, 28);
    expect(second.height, 28);
    expect(second.top - first.bottom, 6);
    expect(tester.getSize(find.byType(CommentFeedback)).height, 62);
    await tester.tapAt(Offset(second.center.dx, first.bottom - 1));
    await tester.pumpAndSettle();
    expect(find.text('评分者3'), findsOneWidget);
    expect(find.textContaining('点评者0'), findsNothing);
  });
  testWidgets(
    'extended capsule targets work inside PostCard and preserve drag scrolling',
    (tester) async {
      await mount(
        tester,
        Column(
          children: [
            PostCard(
              post: Post(
                pid: 90,
                floor: 2,
                author: '作者',
                timeRaw: '',
                content: const [TextBlock('正文')],
                rating: rating(4),
              ),
              isOpening: false,
              commentStyle: true,
            ),
            const SizedBox(height: 1200),
          ],
        ),
      );
      final control = find.descendant(
        of: find.byType(CommentFeedback),
        matching: find.byType(PressScale),
      );
      var rect = tester.getRect(control);
      await tester.tapAt(Offset(rect.center.dx, rect.top - 6));
      await tester.pumpAndSettle();
      expect(find.text('评分者3'), findsOneWidget);
      await tester.tap(control);
      await tester.pumpAndSettle();
      rect = tester.getRect(control);
      final gesture = await tester.startGesture(
        Offset(rect.center.dx, rect.top - 6),
      );
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -60));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('评分者3'), findsNothing);
      expect(
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .pixels,
        greaterThan(0),
      );
    },
  );

  testWidgets('capsules keep a 28dp row and accept taps six pixels above', (
    tester,
  ) async {
    await mount(
      tester,
      Padding(
        padding: const EdgeInsets.all(20),
        child: CommentFeedback(rating: rating(4), comments: comments(2)),
      ),
      width: 600,
    );
    expect(
      tester.getSize(find.byType(CommentFeedback)).height,
      lessThanOrEqualTo(30),
    );
    final wrap = tester.widget<Wrap>(
      find
          .descendant(
            of: find.byType(CommentFeedback),
            matching: find.byType(Wrap),
          )
          .first,
    );
    expect(wrap.runSpacing, 6);
    final presses = find.byType(PressScale);
    final ratingRect = tester.getRect(presses.first);
    expect(ratingRect.height, 28);
    await tester.tapAt(Offset(ratingRect.center.dx, ratingRect.top - 6));
    await tester.pumpAndSettle();
    expect(find.text('评分者3'), findsOneWidget);
    final commentRect = tester.getRect(presses.at(1));
    await tester.tapAt(Offset(commentRect.center.dx, commentRect.top - 6));
    await tester.pumpAndSettle();
    expect(find.textContaining('点评者1'), findsOneWidget);
  });
  testWidgets('comment author content and time share inline text spans', (
    tester,
  ) async {
    const author = '很长的点评作者名字需要正常换行';
    await mount(
      tester,
      const OpeningFeedback(
        comments: [
          PostComment(
            author: author,
            text: '很长的点评内容应该和作者一起正常换行显示',
            timeRaw: '今天',
          ),
        ],
      ),
      width: 180,
    );
    final text = tester.widget<Text>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            (widget.textSpan?.toPlainText().contains('很长的点评内容') ?? false),
      ),
    );
    final span = text.textSpan! as TextSpan;
    expect(span.children!.every((child) => child is TextSpan), isTrue);
    expect(span.toPlainText(), '$author 很长的点评内容应该和作者一起正常换行显示 今天');
    final authorSpan = span.children!.first as TextSpan;
    expect(authorSpan.style!.fontWeight, FontWeight.w600);
    expect(authorSpan.style!.color, AppTokens.light.text);
    expect(tester.takeException(), isNull);
  });
  testWidgets('rating rules use green while comment rules keep separators', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      await mount(
        tester,
        OpeningFeedback(rating: rating(4), comments: comments(3)),
        brightness: brightness,
      );
      final green = brightness == Brightness.light
          ? AppTokens.light.greenLine
          : AppTokens.dark.greenLine;
      final separator = brightness == Brightness.light
          ? AppTokens.light.separator
          : AppTokens.dark.separator;
      final rules = find.byWidgetPredicate(
        (widget) =>
            widget is ColoredBox &&
            (widget.color == green || widget.color == separator),
      );
      expect(rules, findsNWidgets(3));
      expect(tester.widgetList<ColoredBox>(rules).map((box) => box.color), [
        green,
        green,
        separator,
      ]);
    }
  });

  testWidgets('floor strip reason reaches the right inset within 45 percent', (
    tester,
  ) async {
    await mount(
      tester,
      const FloorFeedback(
        rating: PostRating(
          summary: ['参与人数 1', '邪恶指数 +5'],
          entries: [RatingEntry(user: '甲', score: '+5', reason: '理由')],
        ),
      ),
    );
    final rect = tester.getRect(find.text('理由'));
    expect(rect.right, closeTo(390 - 8, .01));
    expect(rect.width, lessThanOrEqualTo(390 * .45));
  });
  testWidgets(
    'opening whole and footer use opening feedback even in comment mode',
    (tester) async {
      final post = Post(
        pid: 2,
        floor: 1,
        author: '首楼',
        timeRaw: '',
        content: const [],
        rating: rating(4),
        comments: comments(3),
      );
      for (final widget in [
        PostCard(post: post, isOpening: true),
        PostCard.footer(post: post, isOpening: true),
        PostCard(post: post, isOpening: true, commentStyle: true),
      ]) {
        await mount(tester, widget);
        expect(find.byType(OpeningFeedback), findsOneWidget);
        expect(find.text('评分者2'), findsOneWidget);
        expect(find.text('评分者3'), findsNothing);
      }
    },
  );
  testWidgets(
    'floor comments expand from two and empty feedback stays absent',
    (tester) async {
      await mount(tester, FloorFeedback(comments: comments(4)));
      expect(find.textContaining('点评者2'), findsNothing);
      await tap(tester, find.text('展开全部 4 条点评'));
      expect(find.textContaining('点评者3'), findsOneWidget);
      await tap(tester, find.text('收起'));
      expect(find.textContaining('点评者2'), findsNothing);
      for (final widget in [const FloorFeedback(), const CommentFeedback()]) {
        await mount(tester, widget);
        expect(find.byType(PressScale), findsNothing);
        expect(tester.getSize(find.byWidget(widget)).height, 0);
      }
    },
  );
  testWidgets('unknown summaries and missing participants are not fabricated', (
    tester,
  ) async {
    const value = PostRating(
      summary: ['站点原文'],
      entries: [RatingEntry(user: '用户', score: '+5')],
    );
    await mount(tester, const OpeningFeedback(rating: value));
    expect(find.text('站点原文'), findsOneWidget);
    expect(find.textContaining('人评分'), findsNothing);
    await mount(tester, const CommentFeedback(rating: value));
    expect(find.text('站点原文'), findsOneWidget);
    expect(find.textContaining('1人'), findsNothing);
  });
  testWidgets('revealed rows fade together and arrows use reveal motion', (
    tester,
  ) async {
    await mount(tester, OpeningFeedback(rating: rating(4)));
    await tester.tap(find.text('展开全部 4 条评分'));
    await tester.pump();
    final opacity = find
        .ancestor(of: find.text('评分者3'), matching: find.byType(Opacity))
        .first;
    expect(tester.widget<Opacity>(opacity).opacity, 0);
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.widget<Opacity>(opacity).opacity, inExclusiveRange(0, 1));
    final arrow = tester.widget<AnimatedRotation>(
      find.byType(AnimatedRotation),
    );
    expect(arrow.turns, .5);
    expect(arrow.duration, AppMotion.revealDuration);
    expect(arrow.curve, AppMotion.revealCurve);
    await tester.pumpAndSettle();
    expect(tester.widget<Opacity>(opacity).opacity, 1);
  });

  testWidgets('opening ratings show three then expand and collapse twelve', (
    tester,
  ) async {
    await mount(tester, OpeningFeedback(rating: rating(12)));
    expect(find.text('评分者2'), findsOneWidget);
    expect(find.text('评分者3'), findsNothing);
    await tap(tester, find.text('展开全部 12 条评分'));
    for (var i = 0; i < 12; i++) {
      expect(find.text('评分者$i'), findsOneWidget);
    }
    await tap(tester, find.text('收起'));
    expect(find.text('评分者2'), findsOneWidget);
    expect(find.text('评分者3'), findsNothing);
  });
  testWidgets('opening comments show two then expand and collapse seven', (
    tester,
  ) async {
    await mount(tester, OpeningFeedback(comments: comments(7)));
    expect(find.textContaining('点评者1'), findsOneWidget);
    expect(find.textContaining('点评者2'), findsNothing);
    await tap(tester, find.text('展开全部 7 条点评'));
    for (var i = 0; i < 7; i++) {
      expect(find.textContaining('点评者$i'), findsOneWidget);
    }
    await tap(tester, find.text('收起'));
    expect(find.textContaining('点评者2'), findsNothing);
  });
  testWidgets('opening hides absent comments and unnecessary expand buttons', (
    tester,
  ) async {
    await mount(tester, OpeningFeedback(rating: rating(3)));
    expect(find.textContaining('展开全部'), findsNothing);
    expect(find.textContaining('点评'), findsNothing);
    await mount(
      tester,
      const OpeningFeedback(
        rating: PostRating(summary: [], entries: []),
      ),
    );
    expect(find.byType(PressScale), findsNothing);
    expect(find.textContaining('人评分'), findsNothing);
  });
  testWidgets(
    'floor single rating uses a strip and multiple ratings fold at two',
    (tester) async {
      await mount(tester, FloorFeedback(rating: rating(1)));
      expect(find.text('评分者0'), findsOneWidget);
      expect(find.text('+5 邪恶指数'), findsOneWidget);
      expect(find.textContaining('展开全部'), findsNothing);
      await mount(tester, FloorFeedback(rating: rating(4)));
      expect(find.text('评分者1'), findsOneWidget);
      expect(find.text('评分者2'), findsNothing);
      await tap(tester, find.text('展开全部 4 条评分'));
      expect(find.text('评分者3'), findsOneWidget);
    },
  );
  testWidgets('single reasonless capsule does not expand', (tester) async {
    await mount(tester, CommentFeedback(rating: rating(1)));
    await tap(tester, find.text('评分者0 +5'));
    expect(find.text('评分者0'), findsNothing);
    final press = tester.widget<PressScale>(find.byType(PressScale));
    expect(press.onTap, isNull);
    expect(find.byType(AnimatedRotation), findsNothing);
  });
  testWidgets(
    'capsules expand independently with all rating and comment rows',
    (tester) async {
      await mount(
        tester,
        CommentFeedback(rating: rating(4), comments: comments(7)),
      );
      await tap(tester, find.text('+55 邪恶指数 · 4人'));
      expect(find.text('评分者3'), findsOneWidget);
      expect(find.textContaining('点评者0'), findsNothing);
      await tap(tester, find.text('点评 7'));
      for (var i = 0; i < 7; i++) {
        expect(find.textContaining('点评者$i'), findsOneWidget);
      }
      expect(find.text('评分者3'), findsOneWidget);
      await tap(tester, find.text('+55 邪恶指数 · 4人'));
      expect(find.text('评分者3'), findsNothing);
      expect(find.textContaining('点评者6'), findsOneWidget);
    },
  );
  testWidgets('single reason and multiple score types enable expansion', (
    tester,
  ) async {
    await mount(tester, CommentFeedback(rating: rating(1, reason: '评分理由')));
    await tap(tester, find.text('评分者0 +5'));
    expect(find.text('评分理由'), findsOneWidget);
    await mount(
      tester,
      const CommentFeedback(
        key: ValueKey('multiple'),
        rating: PostRating(
          summary: ['参与人数 1', '邪恶指数 +5', '家园分 +2'],
          entries: [RatingEntry(user: '单人', score: '+5')],
        ),
      ),
    );
    await tap(tester, find.text('单人 +5'));
    expect(find.text('+2 家园分'), findsOneWidget);
  });
  testWidgets('participants use summary even when entries are incomplete', (
    tester,
  ) async {
    await mount(tester, OpeningFeedback(rating: rating(1, participants: 12)));
    expect(find.text('12 人评分'), findsOneWidget);
    expect(find.text('+8'), findsOneWidget);
    await mount(tester, CommentFeedback(rating: rating(1, participants: 12)));
    expect(find.text('+55 邪恶指数 · 12人'), findsOneWidget);
    await tap(tester, find.text('+55 邪恶指数 · 12人'));
    expect(find.text('评分者0'), findsOneWidget);
  });
  testWidgets('negative detail scores use red in both themes', (tester) async {
    for (final brightness in Brightness.values) {
      await mount(
        tester,
        OpeningFeedback(rating: rating(1, negative: true)),
        brightness: brightness,
      );
      expect(
        tester.widget<Text>(find.text('-5')).style!.color,
        brightness == Brightness.light
            ? AppTokens.light.red
            : AppTokens.dark.red,
      );
    }
  });
  testWidgets(
    'reduced motion expands immediately and controls have 44dp targets',
    (tester) async {
      await mount(tester, OpeningFeedback(rating: rating(12)), reduced: true);
      final button = find.byType(PressScale);
      expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
      await tester.tap(find.text('展开全部 12 条评分'));
      await tester.pump();
      expect(find.text('评分者11'), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
      await mount(
        tester,
        CommentFeedback(rating: rating(4), comments: comments(2)),
        reduced: true,
      );
      expect(tester.getSize(find.byType(CommentFeedback)).height, 28);
      await tester.tap(find.text('点评 2'));
      await tester.pump();
      expect(find.textContaining('点评者1'), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );
  testWidgets('feedback fits narrow comment and floor columns', (tester) async {
    for (final widget in [
      OpeningFeedback(rating: rating(4), comments: comments(2)),
      FloorFeedback(rating: rating(1, reason: '很长的评分理由需要省略')),
      CommentFeedback(rating: rating(4), comments: comments(2)),
    ]) {
      await mount(tester, widget, width: 240);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('comment style renders rating and comment capsules', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: const Scaffold(
          body: PostCard(
            isOpening: false,
            commentStyle: true,
            post: Post(
              pid: 1,
              floor: 2,
              author: '楼层作者',
              timeRaw: '今天',
              content: [TextBlock('正文')],
              rating: PostRating(
                summary: ['参与人数 1', '邪恶指数 +5'],
                entries: [RatingEntry(user: '评分者', score: '+5')],
              ),
              comments: [PostComment(author: '点评者', text: '点评正文')],
            ),
          ),
        ),
      ),
    );
    expect(find.text('评分者 +5'), findsOneWidget);
    expect(find.text('点评 1'), findsOneWidget);
  });
}
