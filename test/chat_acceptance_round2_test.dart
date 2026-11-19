import 'package:chh_app/core/display_time.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/ui/chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'messages_ui_test.dart' show FakeMessages, showPm;

class _TimestampMessages extends FakeMessages {
  final String stamp;
  _TimestampMessages(this.stamp);

  @override
  Future<List<PmMessage>> conversation(
    String viewUrl, {
    bool refresh = true,
  }) async => [PmMessage(author: '对方', text: '本地时间样例', timeRaw: stamp)];
}

RenderParagraph paragraph(WidgetTester tester, Finder text) =>
    tester.renderObject<RenderParagraph>(
      find.descendant(of: text, matching: find.byType(RichText)),
    );

void main() {
  testWidgets('conversation separator renders a clock for today', (
    tester,
  ) async {
    final now = DateTime.now();
    final stamp = '${now.year}-${now.month}-${now.day} 17:41';
    await showPm(tester, _TimestampMessages(stamp));
    expect(find.text(formatDisplayTime(raw: stamp, now: now)), findsOneWidget);
    expect(find.text(stamp), findsNothing);
    expect(find.text('本地时间样例'), findsOneWidget);
  });

  for (final style in AppearanceStyle.values) {
    for (final brightness in Brightness.values) {
      for (final textScale in [1.0, 2.0]) {
        testWidgets(
          'copy preserves bubble layout and text $style $brightness $textScale',
          (tester) async {
            await tester.pumpWidget(
              MaterialApp(
                theme: buildAppTheme(brightness, style),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(textScale)),
                  child: child!,
                ),
                home: const Scaffold(
                  body: Center(
                    child: SizedBox(
                      width: 280,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          ChatBubble(text: '好的 我记录一下', mine: true),
                          SizedBox(height: 80),
                          ChatBubble(
                            text: '第一行保留完整\n第二行需要换行，末尾文字也要完整。',
                            mine: false,
                            joinsPrevious: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
            for (final text in ['好的 我记录一下', '第一行保留完整\n第二行需要换行，末尾文字也要完整。']) {
              final source = paragraph(tester, find.text(text));
              final originalSize = source.size;
              final sourceBubble = find
                  .ancestor(
                    of: find.text(text),
                    matching: find.byType(DecoratedBox),
                  )
                  .first;
              final originalBubbleSize = tester.getSize(sourceBubble);
              final originalDecoration = tester
                  .widget<DecoratedBox>(sourceBubble)
                  .decoration;
              final hold = await tester.startGesture(
                tester.getCenter(find.text(text)),
              );
              await tester.pump(const Duration(milliseconds: 401));
              await hold.up();
              await tester.pumpAndSettle();
              final copy = paragraph(tester, find.text(text).last);
              expect(copy.text.style, source.text.style);
              expect(copy.text.style!.decoration, TextDecoration.none);
              expect(copy.textScaler, source.textScaler);
              expect(copy.size, originalSize);
              expect(copy.didExceedMaxLines, isFalse);
              final copyBubble = find
                  .ancestor(
                    of: find.text(text).last,
                    matching: find.byType(DecoratedBox),
                  )
                  .first;
              expect(tester.getSize(copyBubble), originalBubbleSize);
              expect(
                tester.getCenter(copyBubble),
                tester.getCenter(sourceBubble),
              );
              expect(
                tester.widget<DecoratedBox>(copyBubble).decoration,
                originalDecoration,
              );
              final selection = TextSelection(
                baseOffset: 0,
                extentOffset: text.length,
              );
              expect(
                copy.getBoxesForSelection(selection),
                source.getBoxesForSelection(selection),
              );
              expect(
                paragraph(tester, find.text('复制')).text.style!.decoration,
                TextDecoration.none,
              );
              expect(tester.binding.transientCallbackCount, 0);
              await tester.tapAt(const Offset(5, 5));
              await tester.pumpAndSettle();
              expect(find.text(text), findsOneWidget);
              expect(tester.takeException(), isNull);
            }
          },
        );
      }
    }
  }
}
