import 'dart:io';
import 'dart:ui' as ui;
import 'dart:ui' show BoxHeightStyle;

import 'package:flutter/services.dart';

import 'package:chh_app/design/reading.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/design/typography.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/ui/hit_slop.dart';
import 'package:chh_app/widgets/post_card.dart';
import 'package:chh_app/widgets/post_feedback.dart';
import 'package:chh_app/widgets/rich_content_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Post sample({String time = '今天 12:00', bool feedback = false}) => Post(
  pid: 42,
  floor: 2,
  author: '合成作者',
  timeRaw: time,
  content: const [TextBlock('合成正文')],
  notes: feedback
      ? const [PostNote(PostNoteKind.supplement, '合成补充')]
      : const [],
  rating: feedback
      ? const PostRating(
          summary: ['参与人数 2', '积分 +3'],
          entries: [RatingEntry(user: '评分者', score: '+3', reason: '合成理由')],
        )
      : null,
  comments: feedback
      ? const [PostComment(author: '点评者', text: '合成点评')]
      : const [],
);

Future<void> mount(
  WidgetTester tester,
  Post post, {
  required bool lazy,
  required bool nested,
  VoidCallback? onReply,
  double width = 390,
  double scale = 1,
  bool scroll = false,
  String? fontFamily,
  double devicePixelRatio = 1,
  TargetPlatform platform = TargetPlatform.android,
}) async {
  tester.view.reset();
  tester.view.physicalSize = Size(
    width * devicePixelRatio,
    1200 * devicePixelRatio,
  );
  tester.view.devicePixelRatio = devicePixelRatio;
  await tester.pumpWidget(
    MaterialApp(
      theme: fontFamily == null
          ? buildAppTheme(Brightness.light).copyWith(platform: platform)
          : buildAppTheme(Brightness.light).copyWith(
              platform: platform,
              textTheme: buildAppTheme(Brightness.light).textTheme.apply(
                fontFamily: fontFamily,
                fontFamilyFallback: const ['T9Noto'],
              ),
            ),
      home: MediaQuery(
        data: MediaQueryData(
          textScaler: TextScaler.linear(scale),
          devicePixelRatio: devicePixelRatio,
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            child: RepaintBoundary(
              key: const ValueKey('font-capture'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (lazy) ...[
                    PostCard.header(
                      key: const ValueKey('header'),
                      post: post,
                      isOpening: false,
                      isAuthor: true,
                      commentStyle: true,
                      nested: nested,
                      onReply: onReply,
                    ),
                    PostCard.block(
                      post: post,
                      isOpening: false,
                      commentStyle: true,
                      nested: nested,
                      contentBlock: post.content.single,
                    ),
                    PostCard.footer(
                      key: const ValueKey('footer'),
                      post: post,
                      isOpening: false,
                      commentStyle: true,
                      nested: nested,
                      onReply: onReply,
                    ),
                  ] else
                    PostCard(
                      post: post,
                      isOpening: false,
                      isAuthor: true,
                      commentStyle: true,
                      nested: nested,
                      onReply: onReply,
                    ),
                  if (scroll) const SizedBox(height: 1600),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Rect textSelectionBounds(WidgetTester tester, Finder text) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: text, matching: find.byType(RichText)),
  );
  // 选区框仅用于检查换行范围，不能代表字形墨迹。
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(
      baseOffset: 0,
      extentOffset: paragraph.text.toPlainText().length,
    ),
    boxHeightStyle: BoxHeightStyle.tight,
  );
  expect(boxes, isNotEmpty);
  return boxes
      .map((box) => box.toRect().shift(paragraph.localToGlobal(Offset.zero)))
      .reduce((bounds, box) => bounds.expandToInclude(box));
}

// 使用最终段落的行度量，保留实际字体、fallback、缩放和 strut。
TextPainter paragraphPainter(RenderParagraph paragraph) => TextPainter(
  text: paragraph.text,
  textDirection: paragraph.textDirection,
  textScaler: paragraph.textScaler,
  locale: paragraph.locale,
  strutStyle: paragraph.strutStyle,
  textHeightBehavior: paragraph.textHeightBehavior,
)..layout(maxWidth: paragraph.size.width);

double textBaseline(WidgetTester tester, Finder text) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: text, matching: find.byType(RichText)),
  );
  final painter = paragraphPainter(paragraph);
  final baseline = painter.computeLineMetrics().last.baseline;
  painter.dispose();
  return paragraph.localToGlobal(Offset(0, baseline)).dy;
}

int grayInkBottom(ByteData bytes, int imageWidth, Rect rect) {
  int? bottom;
  for (var y = rect.top.ceil(); y < rect.bottom.floor(); y++) {
    for (var x = rect.left.ceil(); x < rect.right.floor(); x++) {
      final offset = (y * imageWidth + x) * 4;
      final channels = [
        // 将预乘 alpha 合成到白底，再使用实拍审查的灰色阈值。
        bytes.getUint8(offset) + 255 - bytes.getUint8(offset + 3),
        bytes.getUint8(offset + 1) + 255 - bytes.getUint8(offset + 3),
        bytes.getUint8(offset + 2) + 255 - bytes.getUint8(offset + 3),
      ];
      channels.sort();
      if (channels.first > 50 &&
          channels.last < 205 &&
          channels.last - channels.first < 35) {
        bottom = y;
      }
    }
  }
  expect(bottom, isNotNull, reason: '必须检测到真实灰色字形，不能把空白或缺字当作通过');
  return bottom!;
}

// 对最终组件渲染结果取像素；字号缩放、fallback 和字重均参与测量。
Future<int> measureInkDelta(
  WidgetTester tester,
  String timestamp,
  double scale,
) async {
  const ratio = 4.0;
  final timeFinder = find.text(timestamp);
  final replyFinder = find.text('回复');
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('font-capture')),
  );
  final image = (await tester.runAsync(
    () => boundary.toImage(pixelRatio: ratio),
  ))!;
  final bytes = (await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  ))!;
  Rect pixels(Rect rect) => Rect.fromLTRB(
    rect.left * ratio,
    rect.top * ratio,
    rect.right * ratio,
    rect.bottom * ratio,
  );
  final origin = boundary.localToGlobal(Offset.zero);
  final actual =
      grayInkBottom(
        bytes,
        image.width,
        pixels(tester.getRect(replyFinder).shift(-origin)),
      ) -
      grayInkBottom(
        bytes,
        image.width,
        pixels(tester.getRect(timeFinder).shift(-origin)),
      );
  debugPrint('手机字体墨迹：scale=$scale DPR=$ratio 底边差=$actual px');
  final capture = Platform.environment['CHHER_T9_CAPTURE'];
  if (capture != null) {
    await tester.runAsync(() async {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(capture).writeAsBytes(png!.buffer.asUint8List());
    });
  }
  image.dispose();
  return actual;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // 字体只从本机读取；允许其他机器显式指定路径，不下载或提交字体。
  final notoPath = Platform.environment['CHHER_T9_CJK_FONT'];
  final robotoPath = Platform.environment['CHHER_T9_LATIN_FONT'];
  final fontsRequested = notoPath != null || robotoPath != null;
  setUpAll(() async {
    if (!fontsRequested) {
      debugPrint('跳过字体专项：请显式设置 CHHER_T9_CJK_FONT 和 CHHER_T9_LATIN_FONT');
      return;
    }
    expect(notoPath, isNotNull);
    expect(robotoPath, isNotNull);
    for (final entry in {
      'T9Roboto': robotoPath!,
      'T9Noto': notoPath!,
    }.entries) {
      final loader = FontLoader(entry.key);
      loader.addFont(
        File(entry.value).readAsBytes().then(ByteData.sublistView),
      );
      await loader.load();
    }
  });
  for (final lazy in [false, true]) {
    for (final nested in [false, true]) {
      for (final width in [320.0, 390.0]) {
        for (final scale in [0.9, 1.0, 2.0]) {
          testWidgets(
            'device fonts lazy=$lazy nested=$nested width=$width scale=$scale',
            (tester) async {
              addTearDown(tester.view.reset);
              for (final timestamp in [
                '10-30 12:03',
                '2026-11-1 12:03',
                '2026-11-01 12:03:04 / 2026-11-02 13:04:05 / 2026-11-03 14:05:06',
              ]) {
                var replies = 0;
                await mount(
                  tester,
                  sample(time: timestamp),
                  lazy: lazy,
                  nested: nested,
                  width: width,
                  scale: scale,
                  onReply: () => replies++,
                  fontFamily: 'T9Roboto',
                  devicePixelRatio: 4,
                );
                final time = find.text(timestamp);
                final reply = find.text('回复');
                final control = find.byKey(const ValueKey('comment-reply-42'));
                final timeRect = tester.getRect(time);
                final controlRect = tester.getRect(control);
                if (controlRect.top < timeRect.bottom) {
                  expect(
                    textBaseline(tester, time) - textBaseline(tester, reply),
                    closeTo(
                      scale *
                          AppType.sizeFootnote *
                          ReadingMetrics.commentReplyOpticalLiftEm,
                      .01,
                    ),
                  );
                  final inkDelta = await measureInkDelta(
                    tester,
                    timestamp,
                    scale,
                  );
                  expect(
                    inkDelta.abs(),
                    lessThanOrEqualTo(1),
                    reason: '实际字形底边只允许一物理像素抗锯齿误差',
                  );
                  expect(controlRect.left - timeRect.right, closeTo(8, .01));
                } else {
                  expect(controlRect.top - timeRect.bottom, closeTo(12, .01));
                  expect(
                    tester.getTopLeft(reply).dy,
                    greaterThanOrEqualTo(controlRect.top),
                  );
                }
                final target = tester.widget<HitSlopTarget>(
                  find.ancestor(
                    of: control,
                    matching: find.byType(HitSlopTarget),
                  ),
                );
                expect(
                  controlRect.width + target.slop.horizontal,
                  greaterThanOrEqualTo(44),
                );
                expect(
                  controlRect.height + target.slop.vertical,
                  greaterThanOrEqualTo(44),
                );
                for (final point in [
                  timeRect.center,
                  timeRect.bottomLeft + const Offset(1, -1),
                ]) {
                  await tester.tapAt(point);
                  await tester.pumpAndSettle();
                }
                expect(replies, 0);
                await tester.tap(reply);
                await tester.pumpAndSettle();
                await tester.tapAt(
                  controlRect.bottomCenter + const Offset(0, 11),
                );
                await tester.pumpAndSettle();
                expect(replies, 2);
                expect(tester.takeException(), isNull);
              }
            },
            skip: !fontsRequested,
          );
        }
      }
    }
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('optical adjustment scope on $platform', (tester) async {
      addTearDown(tester.view.reset);
      for (final timestamp in ['10-30 12:03', '今天 12:03', '']) {
        await mount(
          tester,
          sample(time: timestamp),
          lazy: false,
          nested: false,
          onReply: () {},
          platform: platform,
        );
        final reply = find.text('回复');
        final padding = tester.widget<Padding>(
          find.ancestor(of: reply, matching: find.byType(Padding)).first,
        );
        final expected =
            platform == TargetPlatform.android && timestamp == '10-30 12:03'
            ? AppType.sizeFootnote * ReadingMetrics.commentReplyOpticalLiftEm
            : 0.0;
        expect(padding.padding, EdgeInsets.only(bottom: expected));
      }
    });
  }

  for (final lazy in [false, true]) {
    for (final nested in [false, true]) {
      final mode =
          '${lazy ? 'lazy' : 'whole'} ${nested ? 'nested' : 'ordinary'}';
      testWidgets('$mode aligns text baselines inside minimum target', (
        tester,
      ) async {
        addTearDown(tester.view.reset);
        final post = sample();
        await mount(tester, post, lazy: lazy, nested: nested, onReply: () {});
        expect(
          textBaseline(tester, find.text('回复')),
          closeTo(textBaseline(tester, find.text(post.timeRaw)), .01),
        );
      });

      testWidgets('$mode time occurs once after feedback beside reply', (
        tester,
      ) async {
        addTearDown(tester.view.reset);
        final post = sample(feedback: true);
        await mount(tester, post, lazy: lazy, nested: nested, onReply: () {});
        final time = find.text(post.timeRaw);
        final reply = find.byKey(const ValueKey('comment-reply-42'));
        expect(time, findsOneWidget);
        expect(find.text('楼主'), findsOneWidget);
        if (lazy) {
          expect(
            find.descendant(
              of: find.byKey(const ValueKey('header')),
              matching: time,
            ),
            findsNothing,
          );
          expect(
            find.descendant(
              of: find.byKey(const ValueKey('footer')),
              matching: time,
            ),
            findsOneWidget,
          );
        }
        final timeRect = tester.getRect(time);
        final replyRect = tester.getRect(reply);
        final body = tester.getRect(find.byType(RichContentText));
        final feedback = tester.getRect(find.byType(CommentFeedback));
        expect(timeRect.top, greaterThan(feedback.bottom));
        expect(timeRect.left, closeTo(body.left, .01));
        expect(replyRect.left - timeRect.right, closeTo(8, .01));
        expect(
          textBaseline(tester, find.text('回复')),
          closeTo(textBaseline(tester, time), .01),
        );
        expect(replyRect.top - feedback.bottom, closeTo(8, .01));
        final timeStyle = tester.widget<Text>(time).style!;
        final replyStyle = tester.widget<Text>(find.text('回复')).style!;
        expect(timeStyle.color, AppTokens.light.text3);
        expect(timeStyle.fontSize, 13);
        expect(replyStyle.color, AppTokens.light.text2);
        expect(replyStyle.fontSize, 13);
        expect(replyStyle.fontWeight, FontWeight.w600);
        expect(tester.getSemantics(reply).label, '回复');
        expect(
          find.descendant(of: reply, matching: find.byType(Icon)),
          findsNothing,
        );
        await tester.tap(find.text('点评 1'));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('2人'));
        await tester.pumpAndSettle();
        expect(find.textContaining('合成点评', findRichText: true), findsOneWidget);
        expect(find.text('合成理由'), findsOneWidget);
        expect(
          tester.getTopLeft(time).dy,
          greaterThan(tester.getBottomLeft(find.byType(CommentFeedback)).dy),
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('$mode absent metadata adds no placeholder', (tester) async {
        addTearDown(tester.view.reset);
        Future<double> bottom(String time, bool enabled) async {
          await mount(
            tester,
            sample(time: time),
            lazy: lazy,
            nested: nested,
            onReply: enabled ? () {} : null,
          );
          expect(find.text('回复'), enabled ? findsOneWidget : findsNothing);
          if (time.isNotEmpty) {
            expect(find.text(time), findsOneWidget);
            expect(
              tester.getTopLeft(find.text(time)).dy,
              greaterThan(
                tester.getBottomLeft(find.byType(RichContentText)).dy,
              ),
            );
          } else if (enabled) {
            expect(
              tester.getTopLeft(find.text('回复')).dx,
              tester.getTopLeft(find.byType(RichContentText)).dx,
            );
          }
          return tester.getBottomLeft(find.byType(PostCard).last).dy;
        }

        final empty = await bottom('', false);
        final bodyBottom = tester
            .getBottomLeft(find.byType(RichContentText))
            .dy;
        expect(empty - bodyBottom, closeTo(12, .01));
        final replyOnly = await bottom('', true);
        final timeOnly = await bottom('今天', false);
        final both = await bottom('今天', true);
        expect(replyOnly, greaterThan(empty));
        expect(timeOnly, greaterThan(empty));
        expect(both, closeTo(replyOnly, .01));
      });

      for (final width in [320.0, 390.0]) {
        for (final scale in [1.0, 2.0]) {
          for (final longTime in [false, true]) {
            testWidgets('$mode width=$width scale=$scale long=$longTime', (
              tester,
            ) async {
              addTearDown(tester.view.reset);
              final post = sample(
                time: longTime
                    ? '合成时间：2026 年 10 月 30 日 星期五 下午 12 时 34 分 56 秒（本地时间）'
                    : '今天',
              );
              var replies = 0;
              await mount(
                tester,
                post,
                lazy: lazy,
                nested: nested,
                width: width,
                scale: scale,
                onReply: () => replies++,
              );
              final time = find.text(post.timeRaw);
              final reply = find.byKey(const ValueKey('comment-reply-42'));
              final timeRect = tester.getRect(time);
              final replyRect = tester.getRect(reply);
              final paragraph = tester.renderObject<RenderParagraph>(
                find.descendant(of: time, matching: find.byType(RichText)),
              );
              expect(paragraph.didExceedMaxLines, isFalse);
              expect(tester.widget<Text>(time).maxLines, isNull);
              expect(timeRect.right, lessThanOrEqualTo(width));
              expect(replyRect.right, lessThanOrEqualTo(width));
              if (longTime) {
                expect(
                  paragraph
                      .getBoxesForSelection(
                        TextSelection(
                          baseOffset: 0,
                          extentOffset: post.timeRaw.length,
                        ),
                      )
                      .length,
                  greaterThan(1),
                );
                expect(replyRect.top - timeRect.bottom, closeTo(12, .01));
                expect(
                  textSelectionBounds(tester, find.text('回复')).top,
                  greaterThan(textSelectionBounds(tester, time).bottom),
                );
              } else {
                expect(
                  textBaseline(tester, find.text('回复')),
                  closeTo(textBaseline(tester, time), .01),
                );
                expect(replyRect.left - timeRect.right, closeTo(8, .01));
              }
              final target = tester.widget<HitSlopTarget>(
                find.ancestor(of: reply, matching: find.byType(HitSlopTarget)),
              );
              expect(
                replyRect.width + target.slop.horizontal,
                greaterThanOrEqualTo(44),
              );
              expect(
                replyRect.height + target.slop.vertical,
                greaterThanOrEqualTo(44),
              );
              for (final point in [
                timeRect.center,
                timeRect.centerRight - const Offset(1, 0),
                timeRect.bottomLeft + const Offset(1, -1),
              ]) {
                await tester.tapAt(point);
                await tester.pumpAndSettle();
              }
              expect(replies, 0);
              await tester.tap(reply);
              await tester.pumpAndSettle();
              expect(replies, 1);
              expect(tester.takeException(), isNull);
            });
          }
        }
      }

      testWidgets(
        '$mode reply transparent target preserves taps and scrolling',
        (tester) async {
          addTearDown(tester.view.reset);
          final targets = <int>[];
          final post = sample(time: '10-30 12:03');
          await mount(
            tester,
            post,
            lazy: lazy,
            nested: nested,
            onReply: () => targets.add(post.pid),
            scroll: true,
          );
          final reply = find.byKey(const ValueKey('comment-reply-42'));
          final rect = tester.getRect(reply);
          final target = tester.widget<HitSlopTarget>(
            find.ancestor(of: reply, matching: find.byType(HitSlopTarget)),
          );
          expect(rect.width + target.slop.horizontal, greaterThanOrEqualTo(44));
          expect(rect.height + target.slop.vertical, greaterThanOrEqualTo(44));
          for (final point in [
            rect.center,
            rect.centerRight + const Offset(7, 0),
            rect.bottomCenter + const Offset(0, 11),
          ]) {
            await tester.tapAt(point);
            await tester.pumpAndSettle();
          }
          expect(targets, [42, 42, 42]);
          final gesture = await tester.startGesture(
            rect.bottomCenter + const Offset(0, 11),
          );
          await gesture.moveBy(const Offset(0, -30));
          await tester.pump();
          await gesture.moveBy(const Offset(0, -60));
          await gesture.up();
          await tester.pumpAndSettle();
          expect(targets, [42, 42, 42]);
          expect(
            tester
                .state<ScrollableState>(find.byType(Scrollable).first)
                .position
                .pixels,
            greaterThan(0),
          );
        },
      );
    }
  }
}
