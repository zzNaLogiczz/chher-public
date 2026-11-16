import 'dart:io';

import 'package:chh_app/core/link_target.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/models/quote_presentation.dart';
import 'package:chh_app/pages/article_page.dart';
import 'package:chh_app/parser/content_walker.dart';
import 'package:chh_app/ui/quote.dart';
import 'package:chh_app/widgets/article_discussion_widgets.dart';
import 'package:chh_app/widgets/post_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

const _signature = '合成作者 发表于 2001-01-02 09:30';
const _reference = PostReference(
  tid: 42,
  pid: 99,
  url: 'https://www.chiphell.com/thread-42-1-1.html',
);
const _quote = QuoteBlock(
  [TextBlock(_signature), TextBlock('合成引用正文')],
  source: _signature,
  reference: _reference,
);

void main() {
  test(
    'parsed synthetic signature is displayed once and keeps reference evidence',
    () {
      final document = html.parse(
        File('test_data/thread_quote_synthetic.html').readAsStringSync(),
      );
      final original = parseContentBlocks(
        document.body!,
        threadId: 2005,
      ).whereType<QuoteBlock>().single;
      final display = quoteForDisplay(original);
      expect(display.source, '测试引用者');
      expect(
        display.children.whereType<TextBlock>().map((b) => b.text).join(),
        '这是一段独立编写的合成引用正文。',
      );
      expect(display.reference, same(original.reference));
      expect(display.unlinkedEvidence, same(original.unlinkedEvidence));
      expect(original.source, contains('发表于'));
      expect(
        original.children.whereType<TextBlock>().map((b) => b.text).join(),
        contains('发表于'),
      );
    },
  );

  test(
    'only a matching first signature is removed and ordinary prose survives',
    () {
      const quote = QuoteBlock([
        TextBlock('不同的正文'),
        TextBlock(_signature),
      ], source: '$_signature 后续正文');
      final display = quoteForDisplay(quote);
      expect(display.source, '合成作者');
      expect(display.children, same(quote.children));
      for (final source in [
        '合成作者',
        '合成作者 发表于 昨天',
        '合成作者 发表于 2001-02-30 09:30',
      ]) {
        final unknown = QuoteBlock(const [
          TextBlock(_signature),
        ], source: source);
        expect(quoteForDisplay(unknown), same(unknown));
      }
    },
  );

  test('stripping across inline spans retains remaining links and smileys', () {
    final target = ExternalLink(Uri.parse('https://example.invalid/quote'));
    const smiley = InlineSmiley('https://example.invalid/smile.png');
    final bodyLink = InlineLink('正文链接', target);
    final quote = QuoteBlock(
      [
        TextBlock(
          '$_signature 正文链接尾句',
          nodes: [
            const InlineText('合成作者 '),
            InlineLink('发表于 2001-01-02 09:30', target),
            const InlineText('\n'),
            bodyLink,
            smiley,
            const InlineText('尾句'),
          ],
        ),
      ],
      source: _signature,
      reference: _reference,
    );
    final display = quoteForDisplay(quote);
    final body = display.children.single as TextBlock;
    expect(body.text, '正文链接尾句');
    expect(body.nodes.first, same(bodyLink));
    expect(body.nodes[1], same(smiley));
    expect(display.reference, same(_reference));
  });

  test('inline mismatch does not remove user content', () {
    const quote = QuoteBlock([
      TextBlock(_signature, nodes: [InlineText('原始文本不同')]),
    ], source: _signature);
    expect(quoteForDisplay(quote).children, same(quote.children));
  });

  for (final entry in ['post', 'article', 'discussion']) {
    testWidgets('$entry displays author once and keeps quoted content', (
      tester,
    ) async {
      PostReference? opened;
      final child = switch (entry) {
        'post' => SingleChildScrollView(
          child: PostCard(
            post: const Post(
              pid: 1,
              floor: 1,
              author: '楼主',
              timeRaw: '',
              content: [_quote],
            ),
            isOpening: true,
            onOpenReference: (value) => opened = value,
          ),
        ),
        'discussion' => const SingleChildScrollView(
          child: DiscussionQuote(quote: _quote),
        ),
        _ => ArticlePage(
          aid: 1,
          title: '合成文章',
          loadPage: (_, _) async => const ArticleContent(
            ArticleDetail(
              aid: 1,
              title: '合成文章',
              content: [_quote],
              page: PageInfo(current: 1, hasNext: false),
            ),
          ),
        ),
      };
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: Scaffold(body: child),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(QuoteView),
          matching: find.text('合成作者'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('发表于'), findsNothing);
      expect(find.text('合成引用正文'), findsOneWidget);
      if (entry == 'post') {
        await tester.tap(find.text('原楼层 ›'));
        expect(opened, same(_reference));
      }
      expect(tester.takeException(), isNull);
    });
  }
}
