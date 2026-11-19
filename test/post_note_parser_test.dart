import 'dart:io';

import 'package:chh_app/models/models.dart';
import 'package:chh_app/parser/post_note_parser.dart';
import 'package:chh_app/parser/thread_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:chh_app/parser/content_walker.dart';

Post _post({
  String time = '2026-11-15 10:00',
  List<ContentBlock> content = const [],
  PostLock? lock,
}) => Post(
  pid: 1,
  floor: 1,
  author: '合成作者',
  timeRaw: time,
  content: content,
  lock: lock,
);

void main() {
  test('supplement preserves original text and accepts both parentheses', () {
    final note = parseSupplement(
      '补充内容 (2026-11-15 11:30):\n第一行 **原文**\n第二行 `代码`',
    )!;
    expect(note.timeRaw, '2026-11-15 11:30');
    expect(note.text, '第一行 **原文**\n第二行 `代码`');
    expect(parseSupplement('补充内容（2026-11-15 11:30）：原文')!.text, '原文');
  });

  test('supplement blank lines collapse without changing nonempty lines', () {
    final note = parseSupplement(
      '补充内容 (2026-11-15 11:30):\n \n\n'
      '第一段 **原文**\n本段第二行\n \n\t\n\u3000\n\n'
      '  第二段保留缩进\n\n \n',
    )!;
    expect(note.text, '第一段 **原文**\n本段第二行\n\n  第二段保留缩进');
  });

  test('supplement empty paragraphs and br paragraphs collapse', () {
    final root = html_parser
        .parseFragment('''<section>
      <i class="pstatus">补充内容 (2026-11-15 11:30):</i>
      <p><br></p><p>  </p><p>第一段</p><p> </p>
      <p><br><br></p><p>&nbsp;</p><p>第二段</p><p><br></p>
      </section>''')
        .children
        .single;
    final notes = <PostNote>[];
    expect(parseContentBlocks(root, notes: notes), isEmpty);
    expect(notes, hasLength(1));
    expect(parseSupplement(notes.single.text)!.text, '第一段\n\n第二段');
  });

  test('unsupported supplement links stay in the original rich body', () {
    final root = html_parser
        .parseFragment('''<section>
      <p>补充内容 (2026-11-15 11:30):
      文字 <a href="https://example.invalid/path?q=1">原始链接</a> 后续</p>
      </section>''')
        .children
        .single;
    final notes = <PostNote>[];
    final blocks = parseContentBlocks(root, notes: notes);
    expect(notes, isEmpty);
    final text = blocks.whereType<TextBlock>().single;
    expect(text.text, contains('原始链接'));
    expect(text.text, contains('后续'));
    final link = text.nodes.whereType<InlineLink>().single;
    expect(link.text, '原始链接');
    expect(link.target.uri.toString(), 'https://example.invalid/path?q=1');
  });

  test(
    'reply supplements join sibling headings and bodies without duplication',
    () {
      final posts = parseThread(
        File('test_data/reply_supplement_synthetic.html').readAsStringSync(),
        tid: 9800,
      ).posts;
      expect(posts.map((p) => p.floor), [1, 2, 3, 4]);
      expect(posts.map((p) => p.notes.length), [1, 1, 1, 2]);
      expect(
        posts.expand((p) => p.notes).map((n) => parseSupplement(n.text)!.text),
        ['楼主的补充原文', '来了个首星\n**按原文显示**', '没有包裹元素的补充\n第二行', '分段补充原文', '第二次补充'],
      );
      expect(
        posts
            .expand((p) => p.content)
            .whereType<TextBlock>()
            .map((b) => b.text),
        ['楼主正文', '回复正文', '另一回复正文', '楼主回复正文'],
      );
      expect(
        parseSupplement(posts[2].notes.single.text)!.timeRaw,
        '2026-10-29 13:52',
      );
    },
  );

  test(
    'split supplements keep unknown, quoted, locked, and media content intact',
    () {
      for (final boundary in [
        'class="quote"',
        'class="locked"',
        'class="aimg_tip"',
        'class="attach_nopermission"',
        'hidden',
      ]) {
        final root = html_parser
            .parseFragment(
              '<section><div $boundary>'
              '<i class="pstatus">补充内容 (2026-10-29 13:51):</i><br>受限补充'
              '</div></section>',
            )
            .children
            .single;
        final notes = <PostNote>[];
        parseContentBlocks(root, notes: notes);
        expect(notes, isEmpty, reason: boundary);
      }
      for (final body in [
        '<i class="pstatus">补充内容 (明天):</i><br>保留原文',
        '<i class="pstatus">补充内容 (2026-02-30 13:51):</i><br>保留原文',
        '<i class="pstatus">补充内容 (2026-10-29 13:51):</i>',
        '<i class="pstatus">补充内容 (2026-10-29 13:51):</i><br>保留原文'
            '<img src="https://example.invalid/synthetic.jpg">',
      ]) {
        final root = html_parser
            .parseFragment('<section>$body</section>')
            .children
            .single;
        final notes = <PostNote>[];
        final blocks = parseContentBlocks(root, notes: notes);
        expect(notes, isEmpty, reason: body);
        expect(blocks.whereType<TextBlock>().first.text, startsWith('补充内容'));
        if (body.contains('<img')) {
          expect(
            blocks.whereType<ImageBlock>().single.url,
            'https://example.invalid/synthetic.jpg',
          );
        }
      }
    },
  );

  test('ambiguous or invalid supplements do not become notes', () {
    for (final text in [
      '前文 补充内容 (2026-11-15 11:30): 原文',
      '补充内容 (明天): 原文',
      '补充内容 (2026-02-30 11:30): 原文',
      '补充内容 (2026-11-15 25:00): 原文',
      '补充内容 (2026-11-15 11:30): ',
      '补充内容 原文',
    ]) {
      expect(parseSupplement(text), isNull, reason: text);
    }
  });

  test(
    'thread extracts recognised notes once without flattening their body',
    () {
      final post = parseThread(
        File('test_data/post_notes_synthetic.html').readAsStringSync(),
        tid: 9701,
      ).posts.single;
      expect(post.notes.length, 4);
      expect(post.notes.first.kind, PostNoteKind.edited);
      expect(
        post.notes
            .skip(1)
            .every((note) => note.kind == PostNoteKind.supplement),
        isTrue,
      );
      expect(parseSupplement(post.notes[1].text)!.text, '第一行 **原文**\n第二行 `代码`');
      expect(parseSupplement(post.notes[2].text)!.text, '第三行\n第四行');
      expect(parseSupplement(post.notes[3].text)!.text, '同段后续内容');
      final body = post.content
          .whereType<TextBlock>()
          .map((b) => b.text)
          .join(' ');
      expect(body, contains('原始正文'));
      expect(body, contains('不能识别的状态，应该留在原文'));
      expect(body, contains('补充内容 (不是时间): 保留正文'));
      expect(body, isNot(contains('第一行')));
      expect(body, isNot(contains('隐藏内容')));
      expect(
        post.content
            .whereType<QuoteBlock>()
            .first
            .children
            .whereType<TextBlock>()
            .single
            .text,
        contains('引文里的补充'),
      );
      expect(post.content.whereType<QuoteBlock>().last.isNotice, isTrue);
      expect(
        post.notes.any(
          (n) =>
              n.text.contains('引文里的') ||
              n.text.contains('受限提示') ||
              n.text.contains('隐藏内容'),
        ),
        isFalse,
      );
    },
  );

  test('edit visibility starts at exactly ten minutes including seconds', () {
    for (final entry in {
      '09:59': false,
      '10:00': false,
      '10:09:59': false,
      '10:10': true,
      '10:10:01': true,
      '11:00': true,
    }.entries) {
      final note = PostNote(
        PostNoteKind.edited,
        '本帖最后由 合成作者 于 2026-11-15 ${entry.key} 编辑',
      );
      expect(showPostEdit(note, _post()), entry.value, reason: entry.key);
    }
  });

  test('invalid and missing times cannot assert edit elapsed time', () {
    final valid = const PostNote(
      PostNoteKind.edited,
      '本帖最后由 合成作者 于 2026-11-15 10:10 编辑',
    );
    expect(showPostEdit(valid, _post(time: '未知时间')), isFalse);
    expect(
      showPostEdit(const PostNote(PostNoteKind.edited, '无法解析的编辑说明'), _post()),
      isFalse,
    );
    expect(postEditedTime('本帖最后由 合成作者 于 2026-02-30 10:10 编辑'), isNull);
    expect(
      postEditedLabel(valid.text, now: DateTime(2026, 11, 19)),
      '最后编辑于 11月15日 10:10',
    );
    expect(postEditedLabel('不能识别'), isNull);
  });

  test('hidden and locked ancestors cannot donate a supplement', () {
    for (final boundary in [
      'hidden',
      'aria-hidden="true"',
      'style="visibility: hidden"',
      'style="DISPLAY: none"',
      'class="locked"',
    ]) {
      final root = html_parser
          .parseFragment(
            '<section><span $boundary><i class="pstatus">'
            '补充内容 (2026-11-15 11:30): 受限文字'
            '</i></span><p>可见文字</p></section>',
          )
          .children
          .single;
      final notes = <PostNote>[];
      final blocks = parseContentBlocks(root, notes: notes);
      expect(notes, isEmpty, reason: boundary);
      expect(blocks.whereType<TextBlock>().map((b) => b.text), ['可见文字']);
    }
  });

  test('a wrapper cannot merge adjacent supplements or discard media', () {
    final root = html_parser
        .parseFragment('''
      <section><div>
      <p>补充内容 (2026-11-15 11:30): 第一项</p>
      <p>补充内容 (2026-11-15 11:31): 第二项</p>
      </div><p>补充内容 (2026-11-15 11:32): 图片
      <img src="https://example.invalid/synthetic.jpg"></p></section>
    ''')
        .children
        .single;
    final notes = <PostNote>[];
    final blocks = parseContentBlocks(root, notes: notes);
    expect(notes.map((n) => parseSupplement(n.text)!.text), ['第一项', '第二项']);
    expect(
      blocks.whereType<ImageBlock>().single.url,
      'https://example.invalid/synthetic.jpg',
    );
    expect(
      blocks.whereType<TextBlock>().single.text,
      contains('补充内容 (2026-11-15 11:32)'),
    );
  });

  test(
    'suppression requires site notice rather than ordinary or quoted text',
    () {
      const text = '作者被禁止或删除 内容自动屏蔽';
      expect(
        isSuppressedPost(
          _post(lock: const PostLock(text: text, needsPassword: false)),
        ),
        isTrue,
      );
      expect(
        isSuppressedPost(
          _post(
            content: const [
              QuoteBlock([TextBlock(text)], isNotice: true),
            ],
          ),
        ),
        isTrue,
      );
      expect(
        isSuppressedPost(_post(content: const [TextBlock(text)])),
        isFalse,
      );
      expect(
        isSuppressedPost(
          _post(
            content: const [
              QuoteBlock([TextBlock(text)]),
            ],
          ),
        ),
        isFalse,
      );
      expect(
        isSuppressedPost(
          _post(lock: const PostLock(text: '本帖需要密码', needsPassword: true)),
        ),
        isFalse,
      );
    },
  );
}
