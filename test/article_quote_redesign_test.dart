import 'package:chh_app/core/link_target.dart';
import 'package:chh_app/core/reading_prefs.dart';
import 'package:chh_app/design/reading.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/article_page.dart';
import 'package:chh_app/ui/quote.dart';
import 'package:chh_app/widgets/rich_content_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'article quotes retain selectable text, inline actions and reading spacing',
    (tester) async {
      final prefs = ReadingPrefsController(directory: () async => null);
      addTearDown(prefs.dispose);
      final short = TextBlock(
        '合成链接',
        nodes: [
          InlineLink(
            '合成链接',
            ExternalLink(Uri.parse('https://example.invalid/quote')),
          ),
        ],
      );
      const long = TextBlock('第一行\n第二行\n第三行\n第四行\n第五行\n第六行');
      await tester.pumpWidget(
        ReadingScope(
          controller: prefs,
          child: MaterialApp(
            theme: buildAppTheme(Brightness.light),
            home: ArticlePage(
              aid: 99,
              title: '合成文章引用',
              loadPage: (_, _) async => ArticleContent(
                ArticleDetail(
                  aid: 99,
                  title: '合成文章引用',
                  content: [
                    QuoteBlock([short], source: '合成作者'),
                    const QuoteBlock([long]),
                  ],
                  page: const PageInfo(current: 1, hasNext: false),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final shortQuote = find.byType(QuoteView).first;
      expect(
        find.descendant(of: shortQuote, matching: find.text('展开')),
        findsNothing,
      );
      final selectable = tester.widget<Text>(
        find.descendant(
          of: shortQuote,
          matching: find.byWidgetPredicate(
            (widget) => widget is Text && widget.textSpan != null,
          ),
        ),
      );
      expect(
        (selectable.textSpan! as TextSpan).children!
            .whereType<TextSpan>()
            .first
            .recognizer,
        isNotNull,
      );
      final quoteContent = find.descendant(
        of: shortQuote,
        matching: find.byType(RichContentText),
      );
      final oldHeight = tester
          .widget<RichContentText>(quoteContent)
          .style!
          .height;
      await prefs.set(
        prefs.prefs.copyWith(lineHeight: ReadingLineHeight.compact),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<RichContentText>(quoteContent).style!.height,
        lessThan(oldHeight!),
      );
      expect(
        find.descendant(
          of: find.byType(QuoteView).last,
          matching: find.byType(SelectableText),
        ),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('展开'));
      await tester.tap(find.text('展开'));
      await tester.pumpAndSettle();
      expect(find.text('收起'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
