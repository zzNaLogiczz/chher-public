import 'dart:convert';
import 'dart:io';

import 'package:chh_app/design/feedback.dart';
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
import 'package:flutter/services.dart';
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

final capsule = find.byKey(const ValueKey('single-rating-capsule'));
final ratingCard = find.byKey(const PageStorageKey('rating-card'));

RenderParagraph paragraph(WidgetTester tester, Finder text) =>
    tester.renderObject<RenderParagraph>(
      find.descendant(of: text, matching: find.byType(RichText)),
    );

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
            expect(ratingCard, findsOneWidget);
            expect(find.text('合成评分人'), findsOneWidget);
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
  testWidgets('rating and comment control keep six pixels between bounds', (
    tester,
  ) async {
    await mount(
      tester,
      CommentFeedback(rating: rating(1), comments: comments(2)),
      width: 240,
    );
    final ratingRect = tester.getRect(capsule);
    final control = find.byType(PressScale);
    final commentRect = tester.getRect(control);
    expect(ratingRect.height, 36);
    expect(commentRect.height, 28);
    expect(commentRect.top - ratingRect.bottom, 6);
    expect(tester.getSize(find.byType(CommentFeedback)).height, 70);
    await tester.tapAt(Offset(commentRect.center.dx, commentRect.top - 1));
    await tester.pumpAndSettle();
    expect(find.text('点评者0'), findsOneWidget);
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
                comments: comments(4),
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
      expect(find.text('点评者3'), findsOneWidget);
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
      expect(find.text('点评者3'), findsNothing);
      expect(
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .pixels,
        greaterThan(0),
      );
    },
  );

  testWidgets('comment capsule keeps a 28dp row and extended tap target', (
    tester,
  ) async {
    await mount(
      tester,
      Padding(
        padding: const EdgeInsets.all(20),
        child: CommentFeedback(comments: comments(2)),
      ),
    );
    expect(tester.getSize(find.byType(CommentFeedback)).height, 28);
    final commentRect = tester.getRect(find.byType(PressScale));
    await tester.tapAt(Offset(commentRect.center.dx, commentRect.top - 6));
    await tester.pumpAndSettle();
    expect(find.text('点评者1'), findsOneWidget);
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
      expect(find.text('评分者2'), findsOneWidget);
      expect(find.text('点评者1'), findsOneWidget);
    }
  });

  testWidgets('single rating capsule has avatar, score and reason in order', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    for (final brightness in Brightness.values) {
      final t = brightness == Brightness.light
          ? AppTokens.light
          : AppTokens.dark;
      for (final (score, scoreColor) in [
        ('+20', ThreadTokens.score(t)),
        ('-20', t.red),
      ]) {
        final value = PostRating(
          summary: ['参与人数 1', '邪恶指数 $score'],
          entries: [RatingEntry(user: '甲', score: score, reason: '样例理由')],
        );
        for (final feedback in [
          FloorFeedback(rating: value),
          CommentFeedback(rating: value),
        ]) {
          await mount(tester, feedback, brightness: brightness);
          final decoration =
              tester.widget<Container>(capsule).decoration as BoxDecoration;
          expect(tester.getSize(capsule).height, 36);
          expect(decoration.borderRadius, BorderRadius.circular(AppRadii.full));
          expect(decoration.color, t.greenSoft);
          final avatar = find.descendant(
            of: capsule,
            matching: find.byType(AvatarImage),
          );
          final name = find.text('甲');
          final scoreText = find.text('$score 邪恶指数');
          final reason = find.text('样例理由');
          expect(tester.getSize(avatar), const Size.square(20));
          expect(tester.widget<Text>(name).style!.fontWeight, FontWeight.w600);
          expect(tester.widget<Text>(name).style!.color, t.text);
          expect(
            tester.widget<Text>(scoreText).style!.fontWeight,
            FontWeight.w700,
          );
          expect(tester.widget<Text>(scoreText).style!.color, scoreColor);
          final reasonText = tester.widget<Text>(reason);
          expect(reasonText.style!.color, t.text2);
          expect(reasonText.maxLines, 1);
          expect(reasonText.overflow, TextOverflow.ellipsis);
          expect(tester.getTopLeft(capsule).dx, 0);
          expect(
            tester.getTopLeft(avatar).dx,
            lessThan(tester.getTopLeft(name).dx),
          );
          expect(
            tester.getTopLeft(name).dx,
            lessThan(tester.getTopLeft(scoreText).dx),
          );
          expect(
            tester.getTopLeft(scoreText).dx,
            lessThan(tester.getTopLeft(reason).dx),
          );
          expect(tester.getTopRight(reason).dx, 390 - 8);
          expect(
            tester
                .getSemantics(reason)
                .getSemanticsData()
                .hasAction(SemanticsAction.tap),
            isFalse,
          );
          expect(find.byType(PressScale), findsNothing);
          expect(ratingCard, findsNothing);
          expect(find.textContaining('★'), findsNothing);
        }
      }
    }
    semantics.dispose();
  });

  testWidgets('298dp rating capsule keeps the full username and score', (
    tester,
  ) async {
    // Ahem gives each Latin letter the width of a CJK glyph. Use the Flutter
    // SDK's bundled Roboto for the Android username width in this fixture.
    await tester.runAsync(() async {
      final config = File('.dart_tool/package_config.json').absolute;
      final packages =
          (jsonDecode(await config.readAsString()) as Map)['packages'] as List;
      final flutter = packages.cast<Map>().singleWhere(
        (package) => package['name'] == 'flutter',
      );
      final flutterPackage = config.uri.resolve(flutter['rootUri'] as String);
      final flutterSdk = Directory.fromUri(flutterPackage).parent.parent;
      final roboto = File.fromUri(
        flutterSdk.uri.resolve(
          'bin/cache/artifacts/material_fonts/Roboto-Bold.ttf',
        ),
      );
      await (FontLoader(
        'RatingTestRoboto',
      )..addFont(roboto.readAsBytes().then(ByteData.sublistView))).load();
    });
    const reason =
        '祝你一路有花开，愿每一段旅程都有新的惊喜，愿沿途风景与你相伴，'
        '愿每个清晨都有阳光，每次出发都带着期待。';
    await mount(
      tester,
      DefaultTextStyle.merge(
        style: const TextStyle(fontFamily: 'RatingTestRoboto'),
        child: const CommentFeedback(
          rating: PostRating(
            summary: ['参与人数 1', '邪恶指数 +5'],
            entries: [
              RatingEntry(user: 'qingshan88', score: '+ 5', reason: reason),
            ],
          ),
        ),
      ),
      width: 298,
    );
    final name = paragraph(tester, find.text('qingshan88'));
    expect(name.didExceedMaxLines, isFalse);
    expect(
      name.size.width,
      lessThanOrEqualTo(
        (298 - 2 * FeedbackMetrics.gap) * FeedbackMetrics.stripUserFraction,
      ),
    );
    expect(paragraph(tester, find.text('+5 邪恶指数')).didExceedMaxLines, isFalse);
    expect(paragraph(tester, find.text(reason)).didExceedMaxLines, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long rating username uses at most 40% of the content width', (
    tester,
  ) async {
    const user = '很长的用户名很长的用户名很长的用户名';
    await mount(
      tester,
      const FloorFeedback(
        rating: PostRating(
          summary: ['参与人数 1', '邪恶指数 +5'],
          entries: [RatingEntry(user: user, score: '+5', reason: '样例理由')],
        ),
      ),
      width: 298,
    );
    final name = paragraph(tester, find.text(user));
    expect(name.didExceedMaxLines, isTrue);
    expect(
      name.size.width,
      (298 - 2 * FeedbackMetrics.gap) * FeedbackMetrics.stripUserFraction,
    );
    expect(find.text('样例理由'), findsOneWidget);
  });

  testWidgets('2x text gives up the rating reason before truncating the name', (
    tester,
  ) async {
    const reason = '祝你一路有花开，愿每一段旅程都有新的惊喜';
    const feedback = CommentFeedback(
      rating: PostRating(
        summary: ['参与人数 1', '邪恶指数 +5'],
        entries: [RatingEntry(user: '甲乙', score: '+ 5', reason: reason)],
      ),
    );
    for (final (width, hasReason, nameTruncated) in [
      (390.0, true, false),
      (298.0, false, false),
      (268.0, false, true),
    ]) {
      await mount(tester, feedback, width: width, scale: 2);
      expect(find.text(reason), hasReason ? findsOneWidget : findsNothing);
      expect(
        paragraph(tester, find.text('甲乙')).didExceedMaxLines,
        nameTruncated,
      );
      final score = paragraph(tester, find.text('+5 邪恶指数'));
      expect(score.didExceedMaxLines, isFalse);
      expect(score.textScaler.scale(FeedbackMetrics.rowSize), 26);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('extremely narrow rating capsule fits the avatar and score', (
    tester,
  ) async {
    const reason = '祝你一路有花开';
    await mount(
      tester,
      const FloorFeedback(
        rating: PostRating(
          summary: ['参与人数 1', '邪恶指数 -5'],
          entries: [RatingEntry(user: '甲乙', score: '- 5', reason: reason)],
        ),
      ),
      width: 64,
      scale: 2,
    );
    final score = find.text('-5 邪恶指数');
    expect(find.text(reason), findsNothing);
    expect(paragraph(tester, score).didExceedMaxLines, isFalse);
    final scoreRect = tester.getRect(score);
    final capsuleRect = tester.getRect(capsule);
    expect(scoreRect.width, greaterThan(0));
    expect(scoreRect.right, lessThanOrEqualTo(capsuleRect.right));
    expect(scoreRect.bottom, lessThanOrEqualTo(capsuleRect.bottom));
    expect(find.byType(AvatarImage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rating card rows compact both signs for display', (
    tester,
  ) async {
    const value = PostRating(
      summary: ['参与人数 2', '邪恶指数 0'],
      entries: [
        RatingEntry(user: '甲', score: '+ 5'),
        RatingEntry(user: '乙', score: '- 5'),
      ],
    );
    for (final feedback in [
      const OpeningFeedback(rating: value),
      const CommentFeedback(rating: value),
    ]) {
      await mount(tester, feedback);
      expect(find.text('+5'), findsOneWidget);
      expect(find.text('-5'), findsOneWidget);
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
  testWidgets('only added rating rows reveal and arrows use select', (
    tester,
  ) async {
    await mount(tester, OpeningFeedback(rating: rating(4)));
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
    expect(find.text('评分者2'), findsOneWidget);
    expect(find.text('评分者3'), findsNothing);
    await tap(tester, find.text('其余 9 人'));
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
    'multi-person floor ratings immediately show a card folded at two',
    (tester) async {
      for (final feedback in [
        FloorFeedback(rating: rating(4)),
        CommentFeedback(rating: rating(4)),
      ]) {
        await mount(tester, feedback);
        expect(ratingCard, findsOneWidget);
        expect(capsule, findsNothing);
        expect(find.text('+55 邪恶指数'), findsOneWidget);
        expect(find.text('4 人评分'), findsOneWidget);
        expect(find.text('评分者0'), findsOneWidget);
        expect(find.text('评分者1'), findsOneWidget);
        expect(find.text('评分者2'), findsNothing);
        expect(find.textContaining('★'), findsNothing);
        await tap(tester, find.text('展开全部 4 条评分'));
        expect(find.text('评分者3'), findsOneWidget);
        await tap(tester, find.text('收起'));
        expect(find.text('评分者2'), findsNothing);
      }
    },
  );

  testWidgets('rating card expansion is stored separately for each reply', (
    tester,
  ) async {
    final bucket = PageStorageBucket();
    Widget floor(int pid) => PageStorage(
      bucket: bucket,
      child: PostCard(
        post: Post(
          pid: pid,
          floor: pid,
          author: '楼层作者',
          timeRaw: '',
          content: const [],
          rating: rating(4),
        ),
        isOpening: false,
      ),
    );
    await mount(tester, floor(2));
    await tap(tester, find.text('展开全部 4 条评分'));
    expect(find.text('评分者3'), findsOneWidget);
    await mount(tester, floor(3));
    expect(find.text('评分者3'), findsNothing);
    await mount(tester, floor(2));
    expect(find.text('评分者3'), findsOneWidget);
  });

  testWidgets('rating card and comment capsule expand independently', (
    tester,
  ) async {
    await mount(
      tester,
      CommentFeedback(rating: rating(4), comments: comments(7)),
    );
    expect(find.text('评分者1'), findsOneWidget);
    expect(find.text('点评者0'), findsNothing);
    await tap(tester, find.text('点评 7'));
    for (var i = 0; i < 7; i++) {
      expect(find.text('点评者$i'), findsOneWidget);
    }
    await tap(tester, find.text('展开全部 4 条评分'));
    expect(find.text('评分者3'), findsOneWidget);
    expect(find.text('点评者6'), findsOneWidget);
    await tap(
      tester,
      find.descendant(of: ratingCard, matching: find.text('收起')),
    );
    expect(find.text('评分者3'), findsNothing);
    expect(find.text('点评者6'), findsOneWidget);
  });

  testWidgets('single rater with multiple credit types shows a card', (
    tester,
  ) async {
    await mount(
      tester,
      const CommentFeedback(
        rating: PostRating(
          summary: ['参与人数 1', '邪恶指数 +5', '家园分 +2'],
          entries: [RatingEntry(user: '单人', score: '+5')],
        ),
      ),
    );
    expect(capsule, findsNothing);
    expect(ratingCard, findsOneWidget);
    expect(find.text('+2 家园分'), findsOneWidget);
    expect(find.text('单人'), findsOneWidget);
  });

  testWidgets('participants use summary even when entries are incomplete', (
    tester,
  ) async {
    for (final feedback in [
      OpeningFeedback(rating: rating(1, participants: 12)),
      CommentFeedback(rating: rating(1, participants: 12)),
    ]) {
      await mount(tester, feedback);
      expect(capsule, findsNothing);
      expect(ratingCard, findsOneWidget);
      expect(find.text('12 人评分'), findsOneWidget);
      expect(find.text('+8'), findsOneWidget);
      expect(find.text('评分者0'), findsOneWidget);
    }
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
        CommentFeedback(comments: comments(2)),
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
    expect(find.text('+5 邪恶指数'), findsOneWidget);
    expect(find.text('评分者'), findsOneWidget);
    expect(find.text('点评 1'), findsOneWidget);
  });
}
