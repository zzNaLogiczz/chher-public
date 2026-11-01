import 'dart:io';

import 'package:chh_app/data/thread_conversation_index.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/parser/content_walker.dart';
import 'package:chh_app/parser/thread_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

const _body = '这段合成正文用于验证无链接引用匹配，后面还有完整的结尾。';
const _prefix = '这段合成正文用于验证无链接引用匹配';
const _signature = '合成作者甲 发表于 2026-2-3 09:05';
List<ContentBlock> _parse(String markup, {int? tid = 123}) =>
    parseContentBlocks(
      html.parseFragment('<div>$markup</div>').children.single,
      threadId: tid,
    );
String _quote({String header = _signature, String body = '$_prefix ...'}) =>
    '<div class="quote"><blockquote><font size="2">$header</font><br>'
    '<font size="2">$body</font></blockquote></div>';
Post _target({
  int pid = 2,
  int floor = 2,
  bool known = true,
  String author = '合成作者甲',
  String time = '2026-02-03 09:05:47',
  List<ContentBlock> content = const [TextBlock(_body)],
}) => Post(
  pid: pid,
  floor: floor,
  floorIsKnown: known,
  author: author,
  timeRaw: time,
  content: content,
);
Post _reply({
  int pid = 4,
  int floor = 4,
  bool known = true,
  String? markup,
  int? tid = 123,
}) => Post(
  pid: pid,
  floor: floor,
  floorIsKnown: known,
  author: '合成回复',
  timeRaw: '',
  content: _parse(markup ?? _quote(), tid: tid),
);
ThreadConversationIndex _build(List<Post> posts, {Set<int> pins = const {}}) =>
    ThreadConversationIndex.build(tid: 123, posts: posts, pinnedRootPids: pins);

void main() {
  test('synthetic font quotes and explicit link share target and root', () {
    final detail = parseThread(
      File('test_data/thread_unlinked_quote_synthetic.html').readAsStringSync(),
      tid: 123,
    );
    final index = _build(detail.posts);
    for (final pid in [4, 9, 34]) {
      expect(index.directTargetFor(pid)?.pid, 2, reason: 'floor $pid');
      expect(index.rootPidFor(pid), 2);
    }
    expect(index.repliesFor(2).map((p) => p.pid), [4, 9, 34]);
    for (final pid in [4, 9]) {
      final quote = index.postsByPid[pid]!.content
          .whereType<QuoteBlock>()
          .single;
      expect(quote.reference, isNull);
      expect(
        quote.children.whereType<TextBlock>().map((b) => b.text).join(),
        contains(_prefix),
      );
    }
  });

  test(
    'full excerpts require equality and whitespace including NBSP normalizes',
    () {
      expect(
        _build([
          _target(),
          _reply(markup: _quote(body: _body)),
        ]).directTargetFor(4)?.pid,
        2,
      );
      expect(
        _build([
          _target(content: const [TextBlock('$_prefix 空白 结尾。')]),
          _reply(markup: _quote(body: '$_prefix&nbsp;\n 空白   结尾。')),
        ]).directTargetFor(4)?.pid,
        2,
      );
      expect(
        _build([
          _target(),
          _reply(markup: _quote(body: _prefix)),
        ]).directTargetFor(4),
        isNull,
      );
    },
  );

  for (final entry in <String, String>{
    'author mismatch': _quote(header: '其他作者 发表于 2026-2-3 09:05'),
    'minute mismatch': _quote(header: '合成作者甲 发表于 2026-2-3 09:06'),
    'missing date': _quote(header: '合成作者甲 发表于 09:05'),
    'invalid day': _quote(header: '合成作者甲 发表于 2026-2-30 09:05'),
    'non-leap day': _quote(header: '合成作者甲 发表于 2026-2-29 09:05'),
    'invalid month': _quote(header: '合成作者甲 发表于 2026-13-3 09:05'),
    'invalid hour': _quote(header: '合成作者甲 发表于 2026-2-3 24:05'),
    'invalid minute': _quote(header: '合成作者甲 发表于 2026-2-3 09:60'),
    'header trailing text': _quote(header: '$_signature 其他文字'),
    'ordinary quote': _quote(header: '只是摘录'),
    'body mismatch': _quote(body: '这段完全不同的正文无法匹配到目标楼层...'),
    'short excerpt': _quote(body: '这段合成正文...'),
    'multiple quotes': '${_quote()}${_quote()}',
    'nested quote': _quote(body: _quote()),
    'notice': '<div class="locked">${_quote()}</div>',
    'invalid link': _quote(
      header:
          '<a href="forum.php?mod=redirect&amp;goto=findpost&amp;pid=0&amp;ptid=123">$_signature</a>',
    ),
    'foreign link': _quote(
      header:
          '<a href="https://example.com/forum.php?mod=redirect&amp;goto=findpost&amp;pid=2&amp;ptid=123">$_signature</a>',
    ),
    'conflicting links': _quote(
      header:
          '<a href="forum.php?mod=redirect&amp;goto=findpost&amp;pid=2&amp;ptid=123">$_signature</a><a href="forum.php?mod=redirect&amp;goto=findpost&amp;pid=3&amp;ptid=123">$_signature</a>',
    ),
    'body anchor': _quote(
      body: '$_prefix ...<a href="https://example.com">链接</a>',
    ),
    'anchor without href': _quote(body: '$_prefix ...<a></a>'),
  }.entries) {
    test('${entry.key} does not infer a target', () {
      expect(
        _build([_target(), _reply(markup: entry.value)]).directTargetFor(4),
        isNull,
      );
    });
  }

  test('explicit cross-thread reference never falls back to local text', () {
    final reply = _reply(
      markup: _quote(
        header:
            '<a href="forum.php?mod=redirect&amp;goto=findpost&amp;pid=2&amp;ptid=999">$_signature</a>',
      ),
    );
    final index = _build([_target(), reply]);
    expect(index.directTargetFor(4)?.tid, 999);
    expect(index.rootPidFor(4), 4);
  });

  test('thread context, known earlier floor and own body are required', () {
    final candidates = [
      _target(floor: 5),
      _target(floor: 4),
      _target(pid: 4),
      _target(known: false),
      _target(author: '合成作者甲乙'),
      _target(time: '2026-2-30 09:05:00'),
      _target(time: '2026-2-3 09:05:60'),
      _target(
        content: const [
          QuoteBlock([TextBlock(_body)]),
          TextBlock('自己的短正文'),
        ],
      ),
      _target(
        content: const [
          QuoteBlock([TextBlock(_body)], isNotice: true),
        ],
      ),
    ];
    for (final target in candidates) {
      expect(_build([target, _reply()]).directTargetFor(4), isNull);
    }
    for (final reply in [
      _reply(known: false),
      _reply(tid: null),
      _reply(tid: 999),
    ]) {
      expect(_build([_target(), reply]).directTargetFor(4), isNull);
    }
  });

  test('author spacing is exact and never normalized into another name', () {
    final reply = _reply(markup: _quote(header: '合成  作者甲 发表于 2026-2-3 09:05'));
    expect(
      _build([_target(author: '合成 作者甲'), reply]).directTargetFor(4),
      isNull,
    );
    expect(
      _build([_target(author: '合成  作者甲'), reply]).directTargetFor(4)?.pid,
      2,
    );
  });

  test('an anchor outside blockquote still prohibits text fallback', () {
    final markup = _quote().replaceFirst('<blockquote>', '<a></a><blockquote>');
    expect(
      _build([_target(), _reply(markup: markup)]).directTargetFor(4),
      isNull,
    );
  });

  test(
    'multiple blockquotes inside one wrapper never infer just the first',
    () {
      final markup = _quote().replaceFirst(
        '</blockquote>',
        '</blockquote><blockquote>另一个独立引用</blockquote>',
      );
      expect(
        _build([_target(), _reply(markup: markup)]).directTargetFor(4),
        isNull,
      );
    },
  );

  test('a post cannot infer itself even when its own text matches', () {
    final self = Post(
      pid: 4,
      floor: 4,
      author: '合成作者甲',
      timeRaw: '2026-2-3 09:05',
      content: [..._parse(_quote()), const TextBlock(_body)],
    );
    expect(_build([self]).directTargetFor(4), isNull);
  });

  test('inference is marked separately and explicit targets take priority', () {
    final inferred = _build([_target(), _reply()]);
    expect(inferred.resolutionFor(4)?.isInferredTarget, isTrue);
    final explicit = _reply(
      markup: _quote(
        header:
            '<a href="forum.php?mod=redirect&amp;goto=findpost&amp;pid=3&amp;ptid=123">$_signature</a>',
      ),
    );
    final index = _build([_target(), _target(pid: 3, floor: 3), explicit]);
    expect(index.directTargetFor(4)?.pid, 3);
    expect(index.resolutionFor(4)?.isInferredTarget, isFalse);
  });

  test('same author and minute need exactly one matching body', () {
    final index = _build([
      _target(),
      _target(
        pid: 3,
        floor: 3,
        content: const [TextBlock('另一篇完全不同的合成正文用于排除不相符候选。')],
      ),
      _reply(),
    ]);
    expect(index.directTargetFor(4)?.pid, 2);
  });

  test('valid leap day and 12-character excerpts are accepted', () {
    const body = '甲乙丙丁戊己庚辛壬癸子丑';
    expect(
      _build([
        _target(time: '2024-2-29 9:05:59', content: const [TextBlock(body)]),
        _reply(
          markup: _quote(header: '合成作者甲 发表于 2024-02-29 09:05', body: body),
        ),
      ]).directTargetFor(4)?.pid,
      2,
    );
    expect(
      _build([
        _target(content: const [TextBlock('甲乙丙丁戊己庚辛壬癸子')]),
        _reply(markup: _quote(body: '甲乙丙丁戊己庚辛壬癸子')),
      ]).directTargetFor(4),
      isNull,
    );
  });

  test('new matching candidates revoke inference on every rebuild', () {
    final reply = _reply();
    final first = _build([_target(), reply]);
    expect(first.directTargetFor(4)?.pid, 2);
    final ambiguous = _build([
      _target(),
      reply,
      _target(pid: 3, floor: 3),
    ], pins: first.roots.map((p) => p.pid).toSet());
    expect(ambiguous.directTargetFor(4), isNull);
    expect(ambiguous.resolutionFor(4)?.isInferredTarget, isFalse);
    expect(ambiguous.rootPidFor(4), 4);
    expect(ambiguous.repliesFor(2), isEmpty);
    expect(first.directTargetFor(4)?.pid, 2);
  });

  test('missing target backfills across pages without moving pinned roots', () {
    final reply = _reply();
    final first = _build([reply]);
    expect(first.directTargetFor(4), isNull);
    final pins = first.roots.map((p) => p.pid).toSet();
    final filled = _build([reply, _target()], pins: pins);
    expect(filled.directTargetFor(4)?.pid, 2);
    expect(filled.rootPidFor(4), 4);
    expect(filled.resolutionFor(4)?.isPinnedRoot, isTrue);
    expect(_build([reply, _target()]).rootPidFor(4), 2);
  });
}
