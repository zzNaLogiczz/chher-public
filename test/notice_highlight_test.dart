import 'package:chh_app/design/motion.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/thread_detail_page.dart';
import 'package:chh_app/widgets/post_card.dart';
import 'package:chh_app/widgets/post_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder _reply() => find.byWidgetPredicate(
  (widget) => widget is PostCard && widget.post.pid == 2,
);

Color _replyColor(WidgetTester tester) => tester
    .widget<ColoredBox>(
      find.ancestor(of: _reply(), matching: find.byType(ColoredBox)).first,
    )
    .color;

AnimationController? _highlight(WidgetTester tester, Finder target) => tester
    .widgetList<AnimatedBuilder>(
      find.ancestor(of: target, matching: find.byType(AnimatedBuilder)),
    )
    .map((widget) => widget.animation)
    .whereType<AnimationController>()
    .where(
      (animation) => animation.duration == AppMotion.noticeHighlightDuration,
    )
    .firstOrNull;

Future<AnimationController> _openNotice(
  WidgetTester tester, {
  required bool reduced,
  bool openingFeedback = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  var gotoReads = 0;
  final pid = openingFeedback ? 1 : 2;
  final target = openingFeedback ? find.byType(OpeningFeedback) : _reply();
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
        child: child!,
      ),
      home: ThreadDetailPage(
        tid: 123,
        title: '通知定位',
        focusPid: pid,
        focusOpeningFeedback: openingFeedback,
        gotoUrl: 'fake://notice/2',
        loadGoto: (url) async {
          expect(url, 'fake://notice/2');
          gotoReads++;
          return ThreadDetail(
            tid: 123,
            fid: 290,
            title: '通知定位',
            posts: [
              for (var n = 1; n <= 24; n++)
                Post(
                  pid: n,
                  floor: n,
                  author: '用户$n',
                  authorUid: '$n',
                  timeRaw: '',
                  content: [
                    TextBlock(
                      openingFeedback && n == 1
                          ? List.filled(30, '主楼正文，评分在正文之后。').join('\n')
                          : '本地楼层$n，无网络提交。',
                    ),
                  ],
                  rating: openingFeedback && n == 1
                      ? const PostRating(
                          summary: ['邪恶指数 +10', '参与人数 1'],
                          entries: [
                            RatingEntry(
                              user: '评分用户',
                              score: '+ 10',
                              reason: '支持分享',
                            ),
                          ],
                        )
                      : null,
                ),
            ],
            page: const PageInfo(current: 1, hasNext: false),
          );
        },
        loadPage: (_, _, _) async => throw StateError('Must use notice URL'),
      ),
    ),
  );
  // Wait only for positioning. pumpAndSettle would consume the highlight.
  for (var n = 0; n < 200; n++) {
    await tester.pump(const Duration(milliseconds: 10));
    final controller = target.evaluate().isEmpty
        ? null
        : _highlight(tester, target);
    if (controller != null && controller.isAnimating) {
      await tester.pump();
      expect(gotoReads, 1);
      expect(target.hitTestable(), findsOneWidget);
      return controller;
    }
  }
  throw StateError('The notice target never started highlighting');
}

Future<void> _at(
  WidgetTester tester,
  AnimationController controller,
  int milliseconds,
) async {
  final elapsed =
      controller.value * AppMotion.noticeHighlightDuration.inMicroseconds;
  final remaining = milliseconds * 1000 - elapsed.round();
  expect(remaining, greaterThanOrEqualTo(0));
  await tester.pump(Duration(microseconds: remaining));
}

void main() {
  test('notice highlight has two pulses, two seconds of hold and a fade', () {
    double at(int ms, {bool reduced = false}) => AppMotion.noticeHighlight(
      ms / AppMotion.noticeHighlightDuration.inMilliseconds,
      reduced: reduced,
    );
    expect(AppMotion.noticeHighlightDuration.inMilliseconds, 5200);
    for (final ms in [0, 1200, 2400, 3400, 4400]) {
      expect(at(ms), closeTo(1, .001));
    }
    for (final ms in [600, 1800]) {
      expect(at(ms), lessThan(.2));
      expect(at(ms, reduced: true), 1);
    }
    expect(at(4800), inExclusiveRange(0, 1));
    expect(at(5200), 0);
    expect(at(5200, reduced: true), 0);
  });

  testWidgets('notice reply flashes twice, holds, fades and does not replay', (
    tester,
  ) async {
    final controller = await _openNotice(tester, reduced: false);
    final high = Color.alphaBlend(
      AppTokens.light.accentFill,
      AppTokens.light.bg,
    );
    final original = AppTokens.light.bg;
    expect(_replyColor(tester), isSameColorAs(high));
    await _at(tester, controller, 600);
    final low = _replyColor(tester);
    expect(low, isSameColorAs(original));
    await _at(tester, controller, 1200);
    expect(_replyColor(tester), isSameColorAs(high));
    await _at(tester, controller, 1800);
    expect(_replyColor(tester), isSameColorAs(low));
    for (final ms in [2400, 3400, 4400]) {
      await _at(tester, controller, ms);
      expect(_replyColor(tester), isSameColorAs(high));
    }
    await _at(tester, controller, 4800);
    expect(_replyColor(tester), isNot(high));
    expect(_replyColor(tester), isNot(original));
    await _at(tester, controller, 5200);
    expect(_replyColor(tester), isSameColorAs(original));
    await tester.pump(const Duration(milliseconds: 1));
    expect(controller.isAnimating, isFalse);

    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    final offset = scroll.position.pixels;
    scroll.position.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(_reply(), findsNothing);
    scroll.position.jumpTo(offset);
    await tester.pumpAndSettle();
    expect(_replyColor(tester), isSameColorAs(original));
    await tester.pump(const Duration(milliseconds: 1));
    expect(controller.isAnimating, isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('feedback retains its palette in $brightness', (tester) async {
      final tokens = brightness == Brightness.light
          ? AppTokens.light
          : AppTokens.dark;
      Future<void> show(double strength) => tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(brightness),
          home: Scaffold(
            body: PostFeedbackHighlight(
              strength: strength,
              child: const OpeningFeedback(
                rating: PostRating(summary: ['邪恶指数 +10'], entries: []),
                comments: [PostComment(author: '点评者', text: '本地点评')],
              ),
            ),
          ),
        ),
      );
      List<Color> backgrounds() => tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(OpeningFeedback),
              matching: find.byType(Container),
            ),
          )
          .where(
            (c) =>
                c.decoration is BoxDecoration &&
                (c.decoration! as BoxDecoration).color != null,
          )
          .map((c) => (c.decoration! as BoxDecoration).color!)
          .toList();
      await show(0);
      final original = backgrounds();
      expect(original, [tokens.greenFill, Colors.transparent]);
      await show(1);
      final highlighted = backgrounds();
      expect(
        highlighted.first,
        isSameColorAs(
          Color.alphaBlend(
            tokens.green.withValues(alpha: .10),
            tokens.greenFill,
          ),
        ),
      );
      expect(
        highlighted.last,
        isSameColorAs(Color.alphaBlend(tokens.fill3, tokens.bg)),
      );
      expect(highlighted.every((c) => c.a == 1), isTrue);
      await show(.5);
      final fading = backgrounds();
      expect(
        fading.first,
        isSameColorAs(Color.lerp(tokens.greenFill, highlighted.first, .5)!),
      );
      await show(0);
      expect(backgrounds(), original);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'opening rating panel shares the notice clock and restores green',
    (tester) async {
      final controller = await _openNotice(
        tester,
        reduced: false,
        openingFeedback: true,
      );
      Color panelColor() {
        final panel = tester
            .widgetList<Container>(
              find.descendant(
                of: find.byType(OpeningFeedback),
                matching: find.byType(Container),
              ),
            )
            .firstWhere(
              (container) =>
                  container.decoration is BoxDecoration &&
                  (container.decoration! as BoxDecoration).color != null,
            );
        return (panel.decoration! as BoxDecoration).color!;
      }

      final high = Color.alphaBlend(
        AppTokens.light.green.withValues(alpha: .10),
        AppTokens.light.greenFill,
      );
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      expect(position.pixels, greaterThan(0));
      expect(panelColor(), isSameColorAs(high));
      await _at(tester, controller, 600);
      final low = panelColor();
      expect(low, isSameColorAs(AppTokens.light.greenFill));
      await _at(tester, controller, 1200);
      expect(panelColor(), isSameColorAs(high));
      await _at(tester, controller, 1800);
      expect(panelColor(), isSameColorAs(low));
      for (final ms in [2400, 3400, 4400]) {
        await _at(tester, controller, ms);
        expect(panelColor(), isSameColorAs(high));
      }
      await _at(tester, controller, 4800);
      expect(panelColor(), isNot(isSameColorAs(high)));
      expect(panelColor(), isNot(isSameColorAs(AppTokens.light.greenFill)));
      await _at(tester, controller, 5200);
      expect(panelColor(), isSameColorAs(AppTokens.light.greenFill));
      await tester.pump(const Duration(milliseconds: 1));
      expect(controller.isAnimating, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reduced motion keeps notice feedback steady then restores it', (
    tester,
  ) async {
    final controller = await _openNotice(tester, reduced: true);
    for (final ms in [600, 1200, 1800, 2400, 3400, 4400]) {
      await _at(tester, controller, ms);
      expect(
        _replyColor(tester),
        isSameColorAs(
          Color.alphaBlend(AppTokens.light.accentFill, AppTokens.light.bg),
        ),
      );
    }
    await _at(tester, controller, 4800);
    expect(
      _replyColor(tester),
      isNot(
        isSameColorAs(
          Color.alphaBlend(AppTokens.light.accentFill, AppTokens.light.bg),
        ),
      ),
    );
    expect(_replyColor(tester), isNot(AppTokens.light.bg));
    await _at(tester, controller, 5200);
    expect(_replyColor(tester), isSameColorAs(AppTokens.light.bg));
    await tester.pump(const Duration(milliseconds: 1));
    expect(controller.isAnimating, isFalse);
    expect(tester.takeException(), isNull);
  });
}
