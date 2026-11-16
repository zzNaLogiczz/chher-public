import 'package:chh_app/design/quote_tokens.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/ui/quote.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _text = '第一行\n第二行\n第三行\n第四行\n第五行\n第六行';

Widget _app(
  Widget child, {
  AppearanceStyle style = AppearanceStyle.cinnabar,
  Brightness brightness = Brightness.light,
  bool reduced = false,
  double scale = 1,
}) => MaterialApp(
  theme: buildAppTheme(brightness, style),
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations: reduced,
        textScaler: TextScaler.linear(scale),
      ),
      child: Scaffold(
        body: SingleChildScrollView(child: SizedBox(width: 320, child: child)),
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'quote reveals only new lines and interruption returns to four lines',
    (tester) async {
      await tester.pumpWidget(
        _app(const QuoteView(author: '合成作者', text: _text)),
      );
      final before = tester.getSize(find.byType(QuoteView));
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: find.text(_text), matching: find.byType(RichText)),
      );
      final origin = paragraph.localToGlobal(Offset.zero);
      final originalSize = paragraph.size;
      await tester.tap(find.text('展开'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(
        tester.getSize(find.byType(QuoteView)).height,
        greaterThan(before.height),
      );
      expect(paragraph.localToGlobal(Offset.zero), origin);
      expect(paragraph.size, originalSize);
      await tester.tap(find.text('收起'));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(QuoteView)), before);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets('original floor action remains independent of expansion', (
    tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(
      _app(
        QuoteView(author: '合成作者', text: _text, onOpenReference: () => opened++),
      ),
    );
    await tester.tap(find.text('原楼层 ›'));
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(find.text('展开'), findsOneWidget);
    expect(find.text('收起'), findsNothing);
  });

  for (final style in AppearanceStyle.values) {
    for (final brightness in Brightness.values) {
      testWidgets('$style $brightness large text respects reduced motion', (
        tester,
      ) async {
        await tester.pumpWidget(
          _app(
            const QuoteView(author: '很长的合成作者名字', text: _text),
            style: style,
            brightness: brightness,
            reduced: true,
            scale: 2,
          ),
        );
        final background =
            tester
                    .widget<DecoratedBox>(
                      find
                          .descendant(
                            of: find.byType(QuoteView),
                            matching: find.byType(DecoratedBox),
                          )
                          .first,
                    )
                    .decoration
                as BoxDecoration;
        expect(background.color, tokensFor(brightness, style).fill);
        expect(
          background.borderRadius,
          BorderRadius.circular(QuoteTokens.radius),
        );
        final before = tester.getSize(find.byType(QuoteView)).height;
        await tester.tap(find.text('展开'));
        await tester.pump();
        expect(
          tester.getSize(find.byType(QuoteView)).height,
          greaterThan(before),
        );
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('rich quote content remains usable after opening', (
    tester,
  ) async {
    var activated = 0;
    await tester.pumpWidget(
      _app(
        QuoteView(
          author: '合成作者',
          text: _text,
          expandedContent: Column(
            children: [
              const Text(_text),
              TextButton(
                onPressed: () => activated++,
                child: const Text('合成链接'),
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('合成链接'), findsNothing);
    await tester.tap(find.text('展开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('合成链接'));
    expect(activated, 1);
    await tester.tap(find.text('收起'));
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('short quote has no expansion or fabricated floor target', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const QuoteView(author: '', text: '合成短引用')));
    expect(find.text('展开'), findsNothing);
    expect(find.text('原楼层 ›'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
