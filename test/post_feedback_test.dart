import 'package:chh_app/design/theme.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/parser/thread_parser.dart';
import 'package:chh_app/widgets/avatar_image.dart';
import 'package:chh_app/widgets/post_card.dart';
import 'package:chh_app/widgets/post_feedback.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/design/thread_tokens.dart';
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

final strip = find.byKey(const ValueKey('post-rating-strip'));

Future<void> openRating(WidgetTester tester) async {
  final disclosure = tester.widget<Semantics>(
    find
        .ancestor(
          of: strip,
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.expanded != null,
          ),
        )
        .first,
  );
  if (disclosure.properties.expanded != true) await tap(tester, strip);
}

Finder ratingText(String text) =>
    find.descendant(of: strip, matching: find.text(text));

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
        await openRating(tester);
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
        await openRating(tester);
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
            text.startsWith('4 ')
                ? ThreadTokens.participants(tokens)
                : text.startsWith('-')
                ? tokens.red
                : ThreadTokens.score(tokens),
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
            await openRating(tester);
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
            expect(find.text('★ $score'), findsOneWidget);
            expect(find.text('合成评分人'), findsOneWidget);
            await tap(tester, strip);
            expect(find.text('合成评分人'), findsNWidgets(2));
            if (rawSummary) expect(find.text('站点原文'), findsOneWidget);
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
            await tap(tester, strip);
            expect(find.text('合成评分人'), findsOneWidget);
            expect(find.text(score), findsNothing);
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
    expect(first.height, 26);
    expect(second.height, 28);
    expect(second.top - first.bottom, 6);
    expect(tester.getSize(find.byType(CommentFeedback)).height, 60);
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
    expect(ratingRect.height, 26);
    await tester.tapAt(Offset(ratingRect.center.dx, ratingRect.top - 6));
    await tester.pumpAndSettle();
    expect(find.text('评分者3'), findsOneWidget);
    final commentRect = tester.getRect(presses.at(1));
    await tester.tapAt(Offset(commentRect.center.dx, commentRect.top - 6));
    await tester.pumpAndSettle();
    expect(find.textContaining('点评者1'), findsOneWidget);
  });
  testWidgets('comment author and time precede the content on its own line', (
    tester,
  ) async {
    const author = '很长的点评作者名字需要正常换行';
    const content = '很长的点评内容应该正常换行显示';
    await mount(
      tester,
      const OpeningFeedback(
        comments: [PostComment(author: author, text: content, timeRaw: '今天')],
      ),
      width: 180,
    );
    final name = tester.widget<Text>(find.text(author));
    expect(name.style!.fontWeight, FontWeight.w600);
    expect(name.style!.color, AppTokens.light.text2);
    expect(
      tester.getTopLeft(find.text(content)).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(find.text('今天')).dy),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('feedback separates content with whitespace without rules', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      await mount(
        tester,
        OpeningFeedback(rating: rating(4), comments: comments(3)),
        brightness: brightness,
      );
      final t = brightness == Brightness.light
          ? AppTokens.light
          : AppTokens.dark;
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is ColoredBox &&
              (widget.color == t.greenLine || widget.color == t.separator),
        ),
        findsNothing,
      );
      await openRating(tester);
      expect(find.text('评分者2'), findsOneWidget);
      expect(find.text('点评者1'), findsOneWidget);
    }
  });

  testWidgets('rating strip leads with a signed score and 16dp avatar', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      final t = brightness == Brightness.light
          ? AppTokens.light
          : AppTokens.dark;
      for (final (score, scoreColor) in [
        ('+20', ThreadTokens.score(t)),
        ('-20', t.red),
      ]) {
        await mount(
          tester,
          CommentFeedback(
            rating: PostRating(
              summary: ['参与人数 1', '邪恶指数 $score'],
              entries: [RatingEntry(user: '甲', score: score)],
            ),
          ),
          brightness: brightness,
        );
        final decoration =
            tester.widget<Container>(strip).decoration as BoxDecoration;
        expect(tester.getSize(strip).height, 26);
        expect(decoration.borderRadius, BorderRadius.circular(9));
        expect(decoration.color, t.greenSoft);
        final scoreText = find.text('★ $score');
        final avatar = find.descendant(
          of: strip,
          matching: find.byType(AvatarImage),
        );
        final name = find.text('甲');
        expect(
          tester.widget<Text>(scoreText).style!.fontWeight,
          FontWeight.w700,
        );
        expect(tester.widget<Text>(scoreText).style!.color, scoreColor);
        expect(tester.widget<Text>(name).style!.color, t.text2);
        expect(tester.getSize(avatar), const Size.square(16));
        expect(tester.getTopLeft(strip).dx, 0);
        expect(
          tester.getTopLeft(avatar).dx,
          greaterThan(tester.getTopLeft(scoreText).dx),
        );
        expect(
          tester.getTopLeft(name).dx,
          greaterThan(tester.getTopLeft(avatar).dx),
        );
      }
    }
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
        if (find.text('评分者2').evaluate().isEmpty) await tap(tester, strip);
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
    await tap(tester, strip);
    expect(find.text('站点原文'), findsOneWidget);
    expect(find.textContaining('人评分'), findsNothing);
    await mount(tester, const CommentFeedback(rating: value));
    await tap(tester, strip);
    expect(find.text('站点原文'), findsOneWidget);
    expect(find.textContaining('1人'), findsNothing);
  });
  testWidgets('only added rating rows reveal and arrows use select', (
    tester,
  ) async {
    await mount(tester, OpeningFeedback(rating: rating(4)));
    await tap(tester, strip);
    final firstRater = find.descendant(
      of: find.byKey(const PageStorageKey('rating-card')),
      matching: find.text('评分者0'),
    );
    final firstPosition = tester.getTopLeft(firstRater);
    await tester.tap(find.text('其余 1 人'));
    await tester.pump();
    final panel = find
        .ancestor(of: find.text('评分者3'), matching: find.byType(Align))
        .first;
    expect(tester.widget<Align>(panel).heightFactor, 0);
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.widget<Align>(panel).heightFactor, inExclusiveRange(0, 1));
    expect(tester.getTopLeft(firstRater), firstPosition);
    expect(
      find.ancestor(of: find.text('评分者3'), matching: find.byType(Opacity)),
      findsNothing,
    );
    await tester.pumpAndSettle();
    expect(tester.widget<Align>(panel).heightFactor, 1);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('opening ratings show three then expand and collapse twelve', (
    tester,
  ) async {
    await mount(tester, OpeningFeedback(rating: rating(12)));
    await tap(tester, strip);
    expect(find.text('评分者2'), findsOneWidget);
    expect(find.text('评分者3'), findsNothing);
    await tap(tester, find.text('其余 9 人'));
    for (var i = 0; i < 12; i++) {
      expect(find.text('评分者$i'), findsNWidgets(i == 0 ? 2 : 1));
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
      expect(find.text('★ +5'), findsOneWidget);
      expect(find.textContaining('展开全部'), findsNothing);
      await mount(tester, FloorFeedback(rating: rating(4)));
      expect(find.text('★ +55'), findsOneWidget);
      expect(ratingText('评分者0'), findsOneWidget);
      expect(ratingText('等 4 人'), findsOneWidget);
      expect(find.text('评分者1'), findsNothing);
      await tap(tester, strip);
      expect(find.text('评分者1'), findsOneWidget);
      expect(find.text('评分者2'), findsNothing);
      await tap(tester, find.text('展开全部 4 条评分'));
      expect(find.text('评分者3'), findsOneWidget);
    },
  );
  testWidgets('multi-rating strip preserves the count beside a long name', (
    tester,
  ) async {
    await mount(
      tester,
      const CommentFeedback(
        rating: PostRating(
          summary: ['参与人数 3', '邪恶指数 +35'],
          entries: [
            RatingEntry(
              user: 'averyveryverylongforumusername2026',
              score: '+20',
            ),
            RatingEntry(user: '乙', score: '+10', reason: '附言'),
            RatingEntry(user: '丙', score: '+5'),
          ],
        ),
      ),
      width: 320,
    );
    expect(find.text('★ +35'), findsOneWidget);
    final count = tester.renderObject<RenderParagraph>(
      find.descendant(of: ratingText('等 3 人'), matching: find.byType(RichText)),
    );
    expect(count.didExceedMaxLines, isFalse);
    expect(tester.getSize(strip).height, 26);
    expect(find.text('附言'), findsNothing);
    await tap(tester, strip);
    expect(find.text('附言'), findsOneWidget);
    await tap(tester, strip);
    expect(find.text('附言'), findsNothing);
  });

  testWidgets('ratings without a summary only sum complete same-credit rows', (
    tester,
  ) async {
    const entries = [
      RatingEntry(user: '甲', score: '+ 20', credit: '邪恶指数'),
      RatingEntry(user: '乙', score: '+10', credit: '邪恶指数'),
      RatingEntry(user: '丙', score: '+5', credit: '邪恶指数'),
    ];
    for (final (summary, rows, label) in [
      (['参与人数 3'], entries, '★ +35'),
      (['参与人数 4'], entries, '★ 评分'),
      (
        ['参与人数 3'],
        [
          ...entries.take(2),
          const RatingEntry(user: '丙', score: '+5', credit: '家园分'),
        ],
        '★ 评分',
      ),
    ]) {
      await mount(
        tester,
        CommentFeedback(
          rating: PostRating(summary: summary, entries: rows),
        ),
      );
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('single reasonless capsule does not expand', (tester) async {
    await mount(tester, CommentFeedback(rating: rating(1)));
    await tap(tester, strip);
    expect(find.text('评分者0'), findsOneWidget);
    expect(find.text('+5'), findsNothing);
    expect(find.byType(PressScale), findsNothing);
    expect(find.byType(AnimatedRotation), findsNothing);
  });
  testWidgets(
    'capsules expand independently with all rating and comment rows',
    (tester) async {
      await mount(
        tester,
        CommentFeedback(rating: rating(4), comments: comments(7)),
      );
      await tap(tester, strip);
      expect(find.text('评分者3'), findsOneWidget);
      expect(find.textContaining('点评者0'), findsNothing);
      await tap(tester, find.text('点评 7'));
      for (var i = 0; i < 7; i++) {
        expect(find.textContaining('点评者$i'), findsOneWidget);
      }
      expect(find.text('评分者3'), findsOneWidget);
      await tap(tester, strip);
      expect(find.text('评分者3'), findsNothing);
      expect(find.textContaining('点评者6'), findsOneWidget);
    },
  );
  testWidgets('single reason and multiple score types enable expansion', (
    tester,
  ) async {
    await mount(tester, CommentFeedback(rating: rating(1, reason: '评分理由')));
    await tap(tester, strip);
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
    await tap(tester, strip);
    expect(find.text('+2 家园分'), findsOneWidget);
  });
  testWidgets('participants use summary even when entries are incomplete', (
    tester,
  ) async {
    await mount(tester, OpeningFeedback(rating: rating(1, participants: 12)));
    expect(ratingText('评分者0'), findsOneWidget);
    expect(ratingText('等 12 人'), findsOneWidget);
    await tap(tester, strip);
    expect(find.text('12 人评分'), findsOneWidget);
    expect(find.text('+8'), findsOneWidget);
    await mount(tester, CommentFeedback(rating: rating(1, participants: 12)));
    expect(ratingText('评分者0'), findsOneWidget);
    expect(ratingText('等 12 人'), findsOneWidget);
    await tap(tester, strip);
    expect(find.text('评分者0'), findsNWidgets(2));
  });
  testWidgets('negative detail scores use red in both themes', (tester) async {
    for (final brightness in Brightness.values) {
      await mount(
        tester,
        OpeningFeedback(rating: rating(1, negative: true)),
        brightness: brightness,
      );
      await openRating(tester);
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
      await tester.tap(strip);
      await tester.pump();
      final button = find.ancestor(
        of: find.text('其余 9 人'),
        matching: find.byType(PressScale),
      );
      expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
      await tester.tap(find.text('其余 9 人'));
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
    expect(find.text('★ +5'), findsOneWidget);
    expect(find.text('评分者'), findsOneWidget);
    expect(find.text('点评 1'), findsOneWidget);
  });
}
