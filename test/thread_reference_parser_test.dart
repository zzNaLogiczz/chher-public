import 'dart:io';

import 'package:chh_app/models/models.dart';
import 'package:chh_app/parser/content_walker.dart';
import 'package:chh_app/parser/thread_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

const _target = 'forum.php?mod=redirect&goto=findpost&pid=700&ptid=42';
const _signature = '测试甲 发表于 2026-10-25 09:30';

String _link(String url, {String text = _signature}) =>
    '<a href="${url.replaceAll('&', '&amp;')}">$text</a>';

List<ContentBlock> _parse(String markup, {int? tid = 42}) => parseContentBlocks(
  html.parseFragment('<div>$markup</div>').children.single,
  threadId: tid,
);

QuoteBlock _quote(String header, {String body = '摘录内容'}) =>
    _parse(
          '<div class="quote"><blockquote>$header<br>$body</blockquote></div>',
        ).single
        as QuoteBlock;

void main() {
  test('synthetic desktop header retains target without claiming parenthood', () {
    final detail = parseThread(
      File('test_data/thread_reference_synthetic.html').readAsStringSync(),
      tid: 42,
      fallbackPage: 3,
    );
    final post = detail.posts.single;
    expect(post.floor, 21);
    expect(post.floorIsKnown, isTrue);
    final quote = post.content.whereType<QuoteBlock>().single;
    expect(quote.reference?.pid, 700);
    expect(quote.reference?.tid, 42);
    expect(
      quote.reference?.url,
      'https://www.chiphell.com/forum.php?mod=redirect&goto=findpost&pid=700&ptid=42',
    );
    final nested = quote.children.whereType<QuoteBlock>().single;
    expect(nested.reference, isNull);
    expect(
      nested.children.whereType<TextBlock>().map((b) => b.text).join(),
      contains('嵌套旧引文'),
    );
    expect(post.content.whereType<TextBlock>().last.text, '这条回复自己的正文。');
  });

  test('direct blockquote and signature wrapper can carry a reference', () {
    final quote =
        _parse('<blockquote><div>${_link(_target)}</div>摘录</blockquote>').single
            as QuoteBlock;
    expect(quote.reference?.pid, 700);
    expect(quote.source, contains('测试甲'));
  });

  test('explicit cross-thread target stays available for navigation', () {
    final quote = _quote(_link(_target.replaceFirst('ptid=42', 'ptid=43')));
    expect(quote.reference?.tid, 43);
  });

  test('missing thread ID is never invented from parse context', () {
    final quote = _quote(_link('forum.php?mod=redirect&goto=findpost&pid=700'));
    expect(quote.reference, isNull);
    expect(quote.children, isNotEmpty);
  });

  test('non-forum callers remain compatible and do not infer a reference', () {
    final quote =
        _parse(
              '<blockquote>${_link(_target)}<br>摘录</blockquote>',
              tid: null,
            ).single
            as QuoteBlock;
    expect(quote.reference, isNull);
  });

  test('ordinary body links are never a reference or a quote', () {
    expect(_parse(_link(_target)).whereType<QuoteBlock>(), isEmpty);
  });

  test('a quote body link is not promoted into its plain signature', () {
    expect(_quote(_signature, body: _link(_target)).reference, isNull);
    expect(
      _quote('$_signature ${_link(_target, text: '正文链接')}').reference,
      isNull,
    );
  });

  test('nested old signature does not provide its outer target', () {
    final quote = _quote(
      '没有目标地址的当前署名',
      body: '<blockquote>${_link(_target)}<br>旧引文</blockquote>',
    );
    expect(quote.reference, isNull);
    expect(quote.children.whereType<QuoteBlock>().single.reference, isNull);
  });

  test(
    'a quote wrapper cannot borrow a nested old blockquote as its header',
    () {
      final quote =
          _parse(
                '<div class="quote"><div class="quote"><blockquote>'
                '${_link(_target)}<br>旧引文'
                '</blockquote></div></div>',
              ).single
              as QuoteBlock;
      expect(quote.reference, isNull);
      expect(quote.children.whereType<QuoteBlock>().single.reference, isNull);
    },
  );

  test('user signature outside the message cannot become a post reference', () {
    final detail = parseThread('''
      <table id="pid810"><tr><td>
      <div class="authi"><strong><a href="space-uid-12.html">作者</a></strong></div>
      <a id="postnum810">21#</a>
      <table><tr><td id="postmessage_810">正常正文</td></tr></table>
      <div class="sign"><blockquote>${_link(_target)}<br>用户签名</blockquote></div>
      </td></tr></table>
      ''', tid: 42);
    expect(detail.posts.single.content.whereType<QuoteBlock>(), isEmpty);
  });

  test('two direct quote blocks retain independent reference candidates', () {
    final quotes = _parse(
      '<blockquote>${_link(_target)}<br>甲</blockquote>'
      '<blockquote>${_link(_target.replaceFirst('700', '701'))}<br>乙</blockquote>',
    ).whereType<QuoteBlock>().toList();
    expect(quotes.map((q) => q.reference?.pid), [700, 701]);
  });

  test('multiple header links never choose one arbitrarily', () {
    expect(_quote('${_link(_target)} ${_link(_target)}').reference, isNull);
    expect(
      _quote(
        '${_link(_target)} '
        '${_link(_target.replaceFirst('700', '701'))}',
      ).reference,
      isNull,
    );
    expect(
      _quote(
        '${_link(_target)} ${_link('https://example.com/$_target')}',
      ).reference,
      isNull,
    );
  });

  for (final entry in <String, String>{
    'foreign host': 'https://example.com/$_target',
    'lookalike host': 'https://www.chiphell.com.example.com/$_target',
    'userinfo': 'https://name@www.chiphell.com/$_target',
    'wrong port': 'https://www.chiphell.com:8443/$_target',
    'wrong scheme': 'http://www.chiphell.com/$_target',
    'wrong path': 'other.php?mod=redirect&goto=findpost&pid=700&ptid=42',
    'wrong module': 'forum.php?mod=viewthread&goto=findpost&pid=700&ptid=42',
    'missing pid': 'forum.php?mod=redirect&goto=findpost&ptid=42',
    'zero pid': _target.replaceFirst('pid=700', 'pid=0'),
    'non-numeric pid': _target.replaceFirst('pid=700', 'pid=abc'),
    'duplicate pid': '$_target&pid=700',
    'conflicting pid': '$_target&pid=701',
    'duplicate tid': '$_target&ptid=42',
    'conflicting tid alias': '$_target&tid=43',
    'duplicate goto': '$_target&goto=lastpost',
  }.entries) {
    test('${entry.key} falls back to readable quote without a relation', () {
      final quote = _quote(_link(entry.value));
      expect(quote.reference, isNull);
      expect(
        quote.children.whereType<TextBlock>().map((b) => b.text).join(),
        contains('摘录内容'),
      );
    });
  }

  test(
    'a findpost link without signature wording is ordinary quoted content',
    () {
      expect(_quote(_link(_target, text: '看看这个链接')).reference, isNull);
    },
  );

  test('fallback floor stays distinguishable from a real first floor', () {
    final detail = parseThread(
      '''
      <table id="pid810"><tr><td>
      <div class="authi"><strong><a href="space-uid-12.html">作者</a></strong></div>
      <a id="postnum810">楼层未知</a><table><tr><td id="postmessage_810">内容</td></tr></table>
      </td></tr></table>
      ''',
      tid: 42,
      fallbackPage: 5,
    );
    expect(detail.posts.single.floor, 1);
    expect(detail.posts.single.floorIsKnown, isFalse);
    expect(detail.page.current, 5);
  });

  test('zero floor is also an unknown fallback', () {
    final detail = parseThread('''
      <table id="pid810"><tr><td>
      <div class="authi"><strong><a href="space-uid-12.html">作者</a></strong></div>
      <a id="postnum810">0#</a></td></tr></table>
      ''', tid: 42);
    expect(detail.posts.single.floorIsKnown, isFalse);
  });

  test('explicit original-poster label is a known first floor', () {
    final detail = parseThread('''
      <table id="pid810"><tr><td>
      <div class="authi"><strong><a href="space-uid-12.html">作者</a></strong></div>
      <a id="postnum810">楼主</a></td></tr></table>
      ''', tid: 42);
    expect(detail.posts.single.floor, 1);
    expect(detail.posts.single.floorIsKnown, isTrue);
  });

  test('existing model constructors keep their defaults', () {
    const quote = QuoteBlock([TextBlock('旧引文')]);
    const post = Post(pid: 1, floor: 1, author: '作者', timeRaw: '', content: []);
    expect(quote.reference, isNull);
    expect(post.floorIsKnown, isTrue);
  });
}
