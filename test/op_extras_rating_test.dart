import 'dart:ui' show Tristate;

import 'package:chh_app/data/rating_repository.dart';
import 'package:chh_app/design/feedback.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/ui/press.dart';
import 'package:chh_app/widgets/post_card.dart';
import 'package:chh_app/widgets/post_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const longReason = '这是一段本地测试附言，完整内容应在名字下方换行显示，末尾也要能够读到。';
PostRating ratings({String reason = longReason, int count = 4}) => PostRating(
  summary: ['参与人数 $count', '邪恶指数 +5'],
  entries: List.generate(
    count,
    (i) =>
        RatingEntry(user: '用户$i', score: '+5', reason: i == 1 ? '好' : reason),
  ),
);

Future<void> mount(
  WidgetTester tester, {
  double width = 390,
  double scale = 1,
  bool reduced = false,
  bool bold = false,
  double? letterSpacing,
  double? wordSpacing,
  AppearanceStyle style = AppearanceStyle.cinnabar,
  Brightness brightness = Brightness.light,
  String reason = longReason,
  PostRating? rating,
  RatingRepository? repository,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(brightness, style),
      home: MediaQuery(
        data: MediaQueryData(
          size: tester.view.physicalSize / tester.view.devicePixelRatio,
          disableAnimations: reduced,
          boldText: bold,
          letterSpacingOverride: letterSpacing,
          wordSpacingOverride: wordSpacing,
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: OpeningFeedback(
                  key: const PageStorageKey('fixture-rating'),
                  rating: rating ?? ratings(reason: reason),
                  repository: repository,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder row(String name) =>
    find.ancestor(of: detailName(name), matching: find.byType(PressHighlight));
Finder detailName(String name) => find.descendant(
  of: find.byKey(const PageStorageKey('rating-card')),
  matching: find.text(name),
);
Finder fullReason() => find.byWidgetPredicate(
  (w) => w is Text && w.data == longReason && w.maxLines == null,
);
Finder summaryReason() => find.byWidgetPredicate(
  (w) => w is Text && w.data == longReason && w.maxLines == 1,
);

void main() {
  testWidgets('only actually truncated rating reasons are interactive', (
    tester,
  ) async {
    await mount(tester);
    expect(row('用户0'), findsOneWidget);
    expect(row('用户1'), findsNothing);
    final short = find.text('好');
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: short, matching: find.byType(RichText)),
    );
    expect(paragraph.didExceedMaxLines, isFalse);
    final long = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: summaryReason().first,
        matching: find.byType(RichText),
      ),
    );
    expect(long.didExceedMaxLines, isTrue);
    await tester.tap(short);
    await tester.pumpAndSettle();
    expect(fullReason(), findsNothing);
  });

  testWidgets('truncation refreshes for width, text and text scale', (
    tester,
  ) async {
    await mount(tester, width: 280, reason: 'abcdefgh');
    expect(row('用户0'), findsOneWidget);
    await mount(tester, width: 700, reason: 'abcdefgh');
    expect(row('用户0'), findsNothing);
    await mount(tester, width: 390, reason: 'abcdefgh');
    expect(row('用户0'), findsNothing);
    await mount(tester, width: 390, scale: 2, reason: 'abcdefgh');
    expect(row('用户0'), findsOneWidget);
    await mount(tester, width: 390, reason: '好');
    expect(row('用户0'), findsNothing);
  });

  testWidgets(
    'truncation matches accessibility text spacing and bold overrides',
    (tester) async {
      for (final spacing in [true, false]) {
        const reason = 'a b c d';
        await mount(tester, reason: reason);
        expect(row('用户0'), findsNothing);
        await mount(
          tester,
          reason: reason,
          bold: true,
          letterSpacing: spacing ? 20 : null,
          wordSpacing: spacing ? null : 100,
        );
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: find.text(reason).first,
            matching: find.byType(RichText),
          ),
        );
        expect(paragraph.didExceedMaxLines, isTrue);
        expect(row('用户0'), findsOneWidget);
        await tester.tap(row('用户0'));
        await tester.pumpAndSettle();
        expect(
          find.byWidgetPredicate(
            (w) => w is Text && w.data == reason && w.maxLines == null,
          ),
          findsOneWidget,
        );
        await tester.tap(detailName('用户0'));
        await tester.pumpAndSettle();
        await mount(tester, reason: reason);
        expect(row('用户0'), findsNothing);
      }
    },
  );

  testWidgets(
    'rating reason reveals below name and reverses without moving header',
    (tester) async {
      await mount(tester);
      final origin = tester.getTopLeft(detailName('用户0'));
      await tester.tap(row('用户0'));
      await tester.pump();
      final panel = find
          .ancestor(of: fullReason(), matching: find.byType(Align))
          .first;
      expect(tester.widget<Align>(panel).heightFactor, 0);
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.widget<Align>(panel).heightFactor, inExclusiveRange(0, 1));
      expect(tester.getTopLeft(detailName('用户0')), origin);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(fullReason()).dx, origin.dx);
      expect(
        tester.getTopLeft(fullReason()).dy,
        greaterThan(tester.getBottomLeft(detailName('用户0')).dy),
      );
      expect(tester.widget<Text>(summaryReason().first).style!.color!.a, 0);
      expect(
        find.ancestor(of: fullReason(), matching: find.byType(Opacity)),
        findsNothing,
      );
      await tester.tap(row('用户0'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.widget<Align>(panel).heightFactor, inExclusiveRange(0, 1));
      await tester.tap(detailName('用户0'));
      await tester.pumpAndSettle();
      expect(tester.widget<Align>(panel).heightFactor, 1);
      await tester.tap(detailName('用户0'));
      await tester.pumpAndSettle();
      expect(fullReason(), findsNothing);
      expect(tester.widget<Text>(summaryReason().first).style!.color!.a, 1);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets('remaining people keep individual expansion after folding', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.text('其余 1 人'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('用户3'));
    await tester.pumpAndSettle();
    expect(fullReason(), findsOneWidget);
    await tester.tap(find.text('收起'));
    await tester.pumpAndSettle();
    expect(find.text('用户3'), findsNothing);
    await tester.tap(find.text('其余 1 人'));
    await tester.pumpAndSettle();
    expect(fullReason(), findsOneWidget);
  });

  testWidgets(
    'expanded reason and remaining rows survive lazy scroll disposal',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: Scaffold(
            body: ListView.builder(
              controller: scroll,
              scrollCacheExtent: const ScrollCacheExtent.pixels(0),
              itemCount: 30,
              itemBuilder: (context, i) => i == 0
                  ? SizedBox(
                      width: 390,
                      child: PostCard.footer(
                        post: Post(
                          pid: 55,
                          floor: 1,
                          author: '作者',
                          timeRaw: '',
                          content: const [],
                          rating: ratings(),
                        ),
                        isOpening: true,
                      ),
                    )
                  : const SizedBox(height: 300),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('其余 1 人'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('用户3'));
      await tester.pumpAndSettle();
      expect(fullReason(), findsOneWidget);
      scroll.jumpTo(3000);
      await tester.pumpAndSettle();
      expect(find.byType(OpeningFeedback), findsNothing);
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      expect(find.text('用户3'), findsOneWidget);
      expect(fullReason(), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets('truncated reason semantics expose full text and toggle hints', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await mount(tester);
    var node = tester.getSemantics(find.bySemanticsLabel('用户0 +5 $longReason'));
    expect(node.getSemanticsData().hint, '展开附言');
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    await tester.tap(row('用户0'));
    await tester.pumpAndSettle();
    node = tester.getSemantics(find.bySemanticsLabel('用户0 +5 $longReason'));
    expect(node.getSemanticsData().hint, '收起附言');
    expect(node.getSemanticsData().flagsCollection.isExpanded, Tristate.isTrue);
    semantics.dispose();
  });

  for (final style in AppearanceStyle.values) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'reason styling and press use tokens for $style $brightness',
        (tester) async {
          await mount(tester, style: style, brightness: brightness);
          final t = tokensFor(brightness, style);
          final press = tester.widget<PressHighlight>(row('用户0'));
          expect(press.color, t.pressed);
          expect(
            press.borderRadius,
            BorderRadius.circular(
              FeedbackMetrics.cardRadius - FeedbackMetrics.inset,
            ),
          );
          final gesture = await tester.startGesture(
            tester.getCenter(row('用户0')),
          );
          await tester.pump();
          expect(
            find.descendant(
              of: row('用户0'),
              matching: find.byWidgetPredicate(
                (w) => w is ColoredBox && w.color == t.pressed,
              ),
            ),
            findsNothing,
          );
          await gesture.up();
          await tester.pump();
          expect(
            find.descendant(
              of: row('用户0'),
              matching: find.byWidgetPredicate(
                (w) => w is ColoredBox && w.color == t.pressed,
              ),
            ),
            findsOneWidget,
          );
          await tester.pumpAndSettle();
          final text = tester.widget<Text>(fullReason());
          expect(text.style!.color, t.text2);
          expect(text.style!.fontSize, 13.5);
          expect(text.style!.height, 1.6);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('reduced motion skips height motion and idle tickers stop', (
    tester,
  ) async {
    await mount(tester, reduced: true, width: 320, scale: 2);
    await tester.tap(row('用户0'));
    await tester.pump();
    final panel = find
        .ancestor(of: fullReason(), matching: find.byType(Align))
        .first;
    expect(tester.widget<Align>(panel).heightFactor, 1);
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    await tester.tap(detailName('用户0'));
    await tester.pump();
    expect(fullReason(), findsNothing);
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
