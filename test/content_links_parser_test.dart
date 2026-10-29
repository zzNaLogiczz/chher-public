import 'dart:io';

import 'package:chh_app/core/link_target.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/parser/content_walker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;

final _fixture = html_parser.parse(
  File('test_data/content_links_synthetic.html').readAsStringSync(),
);

List<ContentBlock> _post(String pid) =>
    parseContentBlocks(_fixture.getElementById('postmessage_$pid')!);

List<ContentBlock> _html(String body) => parseContentBlocks(
  html_parser.parseFragment('<div>$body</div>').children.single,
);

String _plain(List<ContentBlock> blocks) =>
    blocks.whereType<TextBlock>().map((b) => b.text).join('|');

void main() {
  group('合成结构样本', () {
    test('B 站内嵌脚本变成视频块，补上 BV 前缀', () {
      final blocks = _post('1001');
      final videos = blocks.whereType<BilibiliBlock>().toList();
      expect(videos.map((v) => v.video.bvid), ['BV1test00001', 'BV1test00002']);
      // 视频单独成段，前后文字保持原样
      expect(blocks.first, isA<TextBlock>());
      expect((blocks.first as TextBlock).text, startsWith('示例视频一'));
      expect(blocks[1], isA<BilibiliBlock>());
      expect((blocks[2] as TextBlock).text, '示例视频二：中间说明。');
      expect(blocks[3], isA<BilibiliBlock>());
    });

    test('aid 形式的内嵌', () {
      final video = _post('1002').whereType<BilibiliBlock>().single.video;
      expect(video.aid, 1001);
    });

    test('句中的站内链接：网址文字去掉，卡片跟在段落后', () {
      final blocks = _post('1003');
      expect(blocks, hasLength(2));
      expect((blocks[0] as TextBlock).text, '这里是一条示例讨论链接，');
      final card = blocks[1] as SiteLinkBlock;
      expect((card.target as ThreadLink).tid, 2001);
      expect(card.label, isEmpty);
    });

    test('单独成段、文字是标题的站内链接：卡片替代整段', () {
      final blocks = _post('1006');
      final cards = blocks.whereType<SiteLinkBlock>().toList();
      expect(cards.map((c) => (c.target as ThreadLink).tid), [
        2002,
        2003,
        2004,
      ]);
      expect(cards.first.label, '示例装机记录');
      // 标题只出现在卡片上，不再作为文字段落重复
      expect(_plain(blocks), isNot(contains('示例装机记录')));
      expect(_plain(blocks), contains('合成帖子索引'));
    });

    test('站外链接与短链留在文字里，可点击', () {
      final link = (_post('1004').first as TextBlock).nodes
          .whereType<InlineLink>()
          .single;
      expect(link.text, 'https://b23.tv/synthetic');
      expect(link.target, isA<ExternalLink>());

      final ext = (_post('1005').first as TextBlock).nodes
          .whereType<InlineLink>()
          .single;
      expect(ext.target.uri.host, 'example.com');
    });
  });

  group('合成片段', () {
    test('句中带标题文字的站内链接：文字留在句子里', () {
      final blocks = _html('我在<a href="thread-100-1-1.html">上一帖</a>里说过温度。');
      expect((blocks[0] as TextBlock).text, '我在上一帖里说过温度。');
      // 文字留在句子里时不再是可点的行内链接，入口只有卡片
      expect((blocks[0] as TextBlock).nodes.whereType<InlineLink>(), isEmpty);
      expect((blocks[1] as SiteLinkBlock).label, '上一帖');
    });

    test('门户文章链接（样本里没有，合成片段）', () {
      final blocks = _html(
        '<a href="https://www.chiphell.com/article-50001-1.html">2026 秋季散热器横评</a>',
      );
      final card = blocks.single as SiteLinkBlock;
      expect((card.target as ArticleLink).aid, 50001);
    });

    test('同一目标在同一楼层只出一张卡片', () {
      final blocks = _html(
        '<a href="thread-100-1-1.html">thread-100</a><br>'
        '再说一次 https://www.chiphell.com/thread-100-1-1.html',
      );
      expect(blocks.whereType<SiteLinkBlock>(), hasLength(1));
    });

    test('裸网址也识别', () {
      final blocks = _html('看这里 https://example.com/0/1.htm 就知道了');
      final text = blocks.single as TextBlock;
      expect(text.text, '看这里 https://example.com/0/1.htm 就知道了');
      expect(
        text.nodes.whereType<InlineLink>().single.text,
        'https://example.com/0/1.htm',
      );
    });

    test('裸网址后面紧跟中文标点时不把标点算进网址', () {
      final blocks = _html('见 https://example.com/0/1.htm。');
      final link = (blocks.single as TextBlock).nodes
          .whereType<InlineLink>()
          .single;
      expect(link.target.uri.path, '/0/1.htm');
    });

    test('裸网址后面紧跟中文时，中文不算进网址', () {
      final blocks = _html('地址https://www.chiphell.com/thread-1-1-1.html这个帖子');
      expect((blocks[0] as TextBlock).text, '地址这个帖子');
      expect((blocks[1] as SiteLinkBlock).target.key, 'thread:1');
    });

    test('裸网址外面的括号和句末标点不算进网址', () {
      for (final html in [
        '见(https://example.com/a)。',
        '见 https://example.com/a. 下一句',
        '见 https://example.com/a, 还有',
      ]) {
        final link = (_html(html).single as TextBlock).nodes
            .whereType<InlineLink>()
            .single;
        expect(
          link.target.uri.toString(),
          'https://example.com/a',
          reason: html,
        );
      }
    });

    test('网址自带成对括号时保留', () {
      final link =
          (_html('https://en.wikipedia.org/wiki/A_(b) 词条').single as TextBlock)
              .nodes
              .whereType<InlineLink>()
              .single;
      expect(link.text, 'https://en.wikipedia.org/wiki/A_(b)');
    });

    test('a 包着图片时仍是图片块', () {
      final blocks = _html(
        '<a href="https://example.com/big.jpg"><img src="https://example.com/small.jpg"></a>',
      );
      expect(blocks.single, isA<ImageBlock>());
    });

    test('引用块里的链接只保留文字，不出卡片', () {
      final blocks = _html(
        '<div class="quote"><blockquote>原文 <a href="thread-100-1-1.html">thread</a></blockquote></div>',
      );
      final quote = blocks.single as QuoteBlock;
      expect(quote.children.whereType<SiteLinkBlock>(), isEmpty);
      expect((quote.children.single as TextBlock).nodes, isEmpty);
    });

    test('没有链接的段落和以前完全一样', () {
      final blocks = _html('第一段<br>第二段');
      expect(blocks.map((b) => (b as TextBlock).text), ['第一段', '第二段']);
      expect(blocks.every((b) => !(b as TextBlock).hasInline), isTrue);
    });

    test('javascript 链接只保留文字', () {
      final blocks = _html('<a href="javascript:;">展开</a>全文');
      expect((blocks.single as TextBlock).text, '展开全文');
      expect((blocks.single as TextBlock).hasInline, isFalse);
    });
  });
}
