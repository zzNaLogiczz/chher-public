import 'dart:ui' as ui;

import 'package:chh_app/core/link_target.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/thread_page_tokens.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/thread_detail_page.dart';
import 'package:chh_app/ui/nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final style in AppearanceStyle.values) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'long video thread has one progress segment: $style $brightness',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final boundaryKey = GlobalKey();
          final tokens = tokensFor(brightness, style);
          await tester.pumpWidget(
            MaterialApp(
              theme: buildAppTheme(brightness, style),
              home: RepaintBoundary(
                key: boundaryKey,
                child: ThreadDetailPage(
                  tid: 123,
                  title: '',
                  loadPage: (_, _, _) async => ThreadDetail(
                    tid: 123,
                    title: '论坛已支持帖内插入"B站"视频.',
                    posts: [
                      Post(
                        pid: 1,
                        floor: 1,
                        author: '本地样例',
                        timeRaw: '2026-11-15 10:00',
                        content: [
                          for (var i = 0; i < 60; i++) ...[
                            TextBlock('本地正文第 $i 段'),
                            if (i % 10 == 0)
                              BilibiliBlock(
                                BilibiliVideo(
                                  Uri.parse(
                                    'https://www.bilibili.com/video/BV1234567890',
                                  ),
                                  bvid: 'BV1234567890',
                                ),
                              ),
                          ],
                        ],
                      ),
                    ],
                    page: const PageInfo(current: 1, hasNext: false),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final scroll = tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position;
          scroll.jumpTo(scroll.viewportDimension);
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('thread-reading-progress')),
            findsNothing,
          );
          for (final offset in [1000.0, 1500.0, 3000.0]) {
            scroll.jumpTo(offset);
            await tester.pumpAndSettle();
            expect(find.byType(NavOverlay), findsOneWidget);
            expect(
              find.byKey(const ValueKey('thread-reading-progress')),
              findsOneWidget,
            );
            expect(find.byType(LinearProgressIndicator), findsNothing);
            final nav = tester.widget<NavOverlay>(find.byType(NavOverlay));
            final end = 390 * nav.readingProgress!.value;
            final boundary =
                boundaryKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = (await tester.runAsync(() => boundary.toImage()))!;
            final bytes = (await tester.runAsync(
              () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
            ))!;
            final pixels = bytes.buffer.asUint8List();
            // Check the actual raster, including the area after the progress end:
            // another pale segment can pass a widget-count-only assertion.
            for (
              var y = (NavOverlay.barHeight - ThreadPageTokens.progressHeight)
                  .toInt();
              y < NavOverlay.barHeight;
              y++
            ) {
              for (var x = 0; x < image.width; x++) {
                if ((x - end).abs() < 2) {
                  continue; // Fractional edge antialiasing.
                }
                final expected = x < end ? tokens.accent : tokens.bg;
                final pixel = (y * image.width + x) * 4;
                final argb = expected.toARGB32();
                for (var c = 0; c < 3; c++) {
                  expect(
                    pixels[pixel + c],
                    closeTo((argb >> (16 - c * 8)) & 255, 1),
                    reason: 'Unexpected mark at ($x,$y), scroll $offset',
                  );
                }
              }
            }
            image.dispose();
          }
          expect(tester.binding.transientCallbackCount, 0);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
