import 'package:chh_app/data/article_comment_index.dart';
import 'package:chh_app/data/thread_conversation_index.dart';
import 'package:chh_app/models/article_discussion.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/parser/content_walker.dart';
import 'package:chh_app/parser/dom_utils.dart';
import 'package:chh_app/parser/thread_list_parser.dart';
import 'package:chh_app/parser/thread_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

String _post(int pid, String content) =>
    '''
<table id="pid$pid"><tr><td>
<div class="pi"><div class="authi"><a href="space-uid-123.html">作者$pid</a></div></div>
<a id="postnum$pid">$pid#</a>
<div class="pct"><div class="pcb">$content</div></div>
</td></tr></table>''';

const _passwordForm = '''
<div id="ct"><div class="mn"><div class="nfl"><div class="f_c">
<h3>本版块需要密码，您必须在下面输入正确的密码才能浏览这个版块</h3>
<div class="o"><form method="post" action="forum.php?mod=forumdisplay&amp;fid=316&amp;action=pwverify">
<input type="hidden" name="formhash" value="abcd1234">
<input type="password" name="pw"><button>提交</button>
</form></div></div></div></div></div>''';

void main() {
  test(
    'locked floors retain original text and normal floors remain readable',
    () {
      final detail = parseThread('''
<script>var cookiepre = 'abcd_1234_';</script>
${_post(1, '<div class="locked">提示: <em>作者被禁止或删除 内容自动屏蔽</em></div>')}
${_post(2, '<div class="locked">本帖为密码帖 ，请输入密码<input id="postpw_2"><button>提交</button></div>')}
${_post(3, '<table><tr><td id="postmessage_3">正常正文</td></tr></table>')}
''', tid: 42);
      expect(detail.cookiePrefix, 'abcd_1234_');
      expect(detail.posts, hasLength(3));
      expect(detail.posts[0].author, '作者1');
      expect(detail.posts[0].authorUid, '123');
      expect(detail.posts[0].lock?.text, '作者被禁止或删除 内容自动屏蔽');
      expect(detail.posts[0].lock?.needsPassword, isFalse);
      expect(detail.posts[0].content, isEmpty);
      expect(detail.posts[1].lock?.text, '本帖为密码帖，请输入密码');
      expect(detail.posts[1].lock?.needsPassword, isTrue);
      expect(detail.posts[1].content, isEmpty);
      expect(detail.posts[2].lock, isNull);
      expect((detail.posts[2].content.single as TextBlock).text, '正常正文');
    },
  );

  test('floor lock lookup cannot take the next floor lock', () {
    final detail = parseThread('''
${_post(1, '')}
${_post(2, '<div class="locked">该帖被管理员或版主屏蔽</div>')}
''', tid: 42);
    expect(detail.posts[0].lock, isNull);
    expect(detail.posts[1].lock?.text, '该帖被管理员或版主屏蔽');
  });

  for (final entry in <String, Object Function()>{
    'thread': () => parseThread(_passwordForm, tid: 42),
    'list': () => parseThreadList(_passwordForm),
  }.entries) {
    test('${entry.key} detects forum password without a message box', () {
      expect(
        entry.value,
        throwsA(
          isA<PageMessage>()
              .having((m) => m.kind, 'kind', PageMessageKind.forumPassword)
              .having((m) => m.fid, 'fid', 316)
              .having((m) => m.text, 'text', startsWith('本版块需要密码')),
        ),
      );
    });
  }

  test('inline locks use a hint block and remove form controls', () {
    final root = html
        .parseFragment('''<div>前文
<div class="locked">提示：回复可见<input value="隐藏内容"><button>回复</button><button>提交</button></div>
后文</div>''')
        .children
        .single;
    final blocks = parseContentBlocks(root);
    expect((blocks.first as TextBlock).text, '前文');
    final hint = blocks[1] as QuoteBlock;
    expect(hint.isNotice, isTrue);
    expect((hint.children.single as TextBlock).text, '回复可见');
    expect((blocks.last as TextBlock).text, '后文');
  });

  test('inline lock inside visible body is not a floor lock', () {
    final detail = parseThread(
      _post(1, '''
<table><tr><td id="postmessage_1"><div class="locked">需要更高积分<button>提交</button></div></td></tr></table>
'''),
      tid: 42,
    );
    expect(detail.posts.single.lock, isNull);
    expect((detail.posts.single.content.single as QuoteBlock).isNotice, isTrue);
  });

  test('notice hints do not create or obscure forum reply references', () {
    const notice = QuoteBlock([TextBlock('需要更高积分')], isNotice: true);
    final posts = [
      const Post(
        pid: 2,
        floor: 2,
        author: '甲',
        timeRaw: '',
        content: [TextBlock('正文')],
      ),
      const Post(pid: 3, floor: 3, author: '乙', timeRaw: '', content: [notice]),
      const Post(
        pid: 4,
        floor: 4,
        author: '丙',
        timeRaw: '',
        content: [
          notice,
          QuoteBlock([
            TextBlock('引用'),
          ], reference: PostReference(tid: 42, pid: 2, url: '')),
        ],
      ),
    ];
    final index = ThreadConversationIndex.build(tid: 42, posts: posts);
    expect(index.statusFor(3), ThreadConversationStatus.independent);
    expect(index.directTargetFor(4)?.pid, 2);
    expect(index.repliesFor(2).map((post) => post.pid), [4]);
  });

  test('portal notices remain body text and never become reply references', () {
    const source = ArticleComment(
      cid: 1,
      author: '甲',
      content: [TextBlock('正文')],
    );
    const notice = ArticleComment(
      cid: 2,
      author: '乙',
      content: [
        QuoteBlock([TextBlock('甲: 正文')], isNotice: true),
      ],
    );
    final index = ArticleCommentIndex.build([source, notice]);
    expect(index.targetOf(2), isNull);
    expect(ArticleCommentIndex.bodyText(notice), '甲: 正文');
  });

  test('locked text strips Chinese prefix and repeated whitespace', () {
    final locked = html
        .parseFragment('<div>提示：  此帖仅作者可见&nbsp;  </div>')
        .children
        .single;
    expect(cleanLockedText(locked), '此帖仅作者可见');
  });
}
