import 'dart:io';

import 'package:chh_app/models/models.dart';
import 'package:chh_app/parser/content_walker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

void main() {
  test('synthetic quote DOM retains its explicit PID and PTID', () {
    // Independently written HTML preserves the parser boundary without user data.
    final document = html.parse(
      File('test_data/thread_quote_synthetic.html').readAsStringSync(),
    );
    final blocks = parseContentBlocks(document.body!, threadId: 2005);
    final quote = blocks.whereType<QuoteBlock>().single;

    expect(quote.reference?.pid, 9001);
    expect(quote.reference?.tid, 2005);
    expect(
      quote.reference?.url,
      'https://www.chiphell.com/forum.php?mod=redirect&goto=findpost&pid=9001&ptid=2005',
    );
    expect(quote.source, contains('测试引用者'));
    expect(
      quote.children.whereType<TextBlock>().map((block) => block.text).join(),
      contains('合成引用正文'),
    );
  });
}
