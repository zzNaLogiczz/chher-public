import 'package:chh_app/models/models.dart';
import 'package:chh_app/parser/thread_parser.dart';
import 'package:flutter_test/flutter_test.dart';

// 全部为合成数据，不使用真实帖子或附件地址。
String attachmentImage(String id, {String? attributes}) =>
    '<img id="aimg_$id" ${attributes ?? 'src="https://example.invalid/$id.jpg"'}>';

String attachment(String images) =>
    '''
<div class="pattl"><ignore_js_op><dl class="tattl attm"><dd>
<p>合成附件名、下载次数</p><div class="mbn savephotop">$images</div>
<div class="aimg_tip">合成上传信息</div>
</dd></dl></ignore_js_op></div>''';

String attachmentPost(
  int pid, {
  String? body = '合成正文',
  String extra = '',
  String outside = '',
}) =>
    '''
<table id="pid$pid"><tr><td>
<div class="authi"><strong><a href="space-uid-$pid.html">合成作者$pid</a></strong></div>
<a id="postnum$pid">$pid#</a>
<div class="pct"><div class="pcb"><div class="t_fsz">
${body == null ? '' : '<table><tr><td id="postmessage_$pid">$body</td></tr></table>'}
$extra</div></div></div>$outside
</td></tr></table>''';

List<String> imageUrls(Post post) =>
    post.content.whereType<ImageBlock>().map((image) => image.url).toList();

void main() {
  for (final identity in [
    'aid="700"',
    'id="aimg_700"',
    'id="aimg_700" aid="700"',
  ]) {
    test('正文相同附件身份不同URL不补图，保留正文重复：$identity', () {
      final inline = '<img $identity src="https://example.invalid/thumb.jpg">';
      final post = parseThread(
        attachmentPost(
          1,
          body: '$inline<br>$inline',
          extra: attachment(
            '<img id="aimg_700" aid="700" src="https://example.invalid/full.jpg">',
          ),
        ),
        tid: 42,
      ).posts.single;
      expect(imageUrls(post), [
        'https://example.invalid/thumb.jpg',
        'https://example.invalid/thumb.jpg',
      ]);
    });
  }

  test('纯外置同aid或aimg身份不同URL仅追加第一次，保持不同附件顺序', () {
    final post = parseThread(
      attachmentPost(
        1,
        extra: attachment('''
<img id="aimg_first" aid="700" src="https://example.invalid/first.jpg">
<img id="aimg_second" aid="700" src="https://example.invalid/second.jpg">
<img id="aimg_700" src="https://example.invalid/third.jpg">
<img id="aimg_701" src="https://example.invalid/other.jpg">
'''),
      ),
      tid: 42,
    ).posts.single;
    expect(imageUrls(post), [
      'https://example.invalid/first.jpg',
      'https://example.invalid/other.jpg',
    ]);
  });

  test('URL去重仍生效并记录合法附件的身份与URL别名', () {
    final post = parseThread(
      attachmentPost(
        1,
        body: '<img src="/synthetic.jpg">',
        extra: attachment('''
<img id="aimg_700" src="https://www.chiphell.com/synthetic.jpg">
<img id="aimg_700" src="https://example.invalid/full.jpg">
<img id="aimg_alias" src="https://example.invalid/full.jpg">
'''),
      ),
      tid: 42,
    ).posts.single;
    expect(imageUrls(post), ['https://www.chiphell.com/synthetic.jpg']);
  });

  for (final boundary in [
    'class="locked"',
    'class="attach_nopermission"',
    'class="quote"',
    'style="display:none"',
    'hidden',
    'aria-hidden="true"',
  ]) {
    for (final inBody in [false, true]) {
      test('隐藏权限引用节点不占用附件身份：$boundary，正文=$inBody', () {
        final blocked =
            '<div $boundary><img id="aimg_700" aid="700" src="https://example.invalid/blocked.jpg"></div>';
        final post = parseThread(
          attachmentPost(
            1,
            body: inBody ? blocked : '合成正文',
            extra: attachment(
              '${inBody ? '' : blocked}<img id="aimg_700" aid="700" src="https://example.invalid/visible.jpg">',
            ),
          ),
          tid: 42,
        ).posts.single;
        expect(
          imageUrls(
            post,
          ).where((url) => url == 'https://example.invalid/visible.jpg'),
          hasLength(1),
        );
      });
    }
  }

  test('占位和文件图标不占用附件身份', () {
    final post = parseThread(
      attachmentPost(
        1,
        body: '<img id="aimg_700" src="static/image/common/none.gif">',
        extra: attachment('''
<img id="aimg_700" src="static/image/filetype/zip.gif">
<img id="aimg_700" src="https://example.invalid/visible.jpg">
'''),
      ),
      tid: 42,
    ).posts.single;
    expect(imageUrls(post), ['https://example.invalid/visible.jpg']);
  });

  for (final identity in [
    'id="aimg_0" aid="0"',
    'id="aimg_-700" aid="-700"',
    'id="aimg_invalid" aid="invalid"',
    'id="aimg_700x" aid="700x"',
    'id="aimg_700" aid="701"',
  ]) {
    test('无效或互相冲突的身份不合并不同URL：$identity', () {
      final post = parseThread(
        attachmentPost(
          1,
          body: '<img $identity src="https://example.invalid/first.jpg">',
          extra: attachment(
            '<img $identity src="https://example.invalid/second.jpg">',
          ),
        ),
        tid: 42,
      ).posts.single;
      expect(imageUrls(post), [
        'https://example.invalid/first.jpg',
        'https://example.invalid/second.jpg',
      ]);
    });
  }

  test('同一身份仅在当前楼层去重，不受相邻或嵌套楼层影响', () {
    final nested = attachmentPost(
      3,
      body: '<img id="aimg_700" src="https://example.invalid/nested.jpg">',
    );
    final posts = parseThread(
      attachmentPost(
            1,
            body: '<img id="aimg_700" src="https://example.invalid/first.jpg">',
          ) +
          attachmentPost(
            2,
            body: '合成正文',
            extra:
                nested +
                attachment(
                  '<img id="aimg_700" src="https://example.invalid/second.jpg">',
                ),
          ),
      tid: 42,
    ).posts;
    expect(imageUrls(posts[0]), ['https://example.invalid/first.jpg']);
    expect(imageUrls(posts[1]), ['https://example.invalid/second.jpg']);
    expect(imageUrls(posts[2]), ['https://example.invalid/nested.jpg']);
  });

  test('首楼与回复楼补充正文外图片，保留正文和附件的顺序', () {
    final posts = parseThread(
      attachmentPost(1, extra: attachment(attachmentImage('1'))) +
          attachmentPost(
            2,
            body: '前文<br>后文',
            extra: attachment(attachmentImage('2') + attachmentImage('3')),
          ),
      tid: 42,
    ).posts;
    expect(imageUrls(posts[0]), ['https://example.invalid/1.jpg']);
    expect(imageUrls(posts[1]), [
      'https://example.invalid/2.jpg',
      'https://example.invalid/3.jpg',
    ]);
    expect(posts[1].content.map((block) => block.runtimeType), [
      TextBlock,
      TextBlock,
      ImageBlock,
      ImageBlock,
    ]);
    expect(posts[1].content.whereType<TextBlock>().map((b) => b.text), [
      '前文',
      '后文',
    ]);
  });

  test('只对新增附件去重，正文刻意重复与引用保持原样', () {
    const url = '/data/attachment/forum/synthetic.jpg';
    final inline = attachmentImage('10', attributes: 'file="$url"');
    final post = parseThread(
      attachmentPost(
        1,
        body:
            '$inline<br>$inline<div class="quote"><blockquote>合成引用</blockquote></div>',
        extra: attachment(
          attachmentImage(
                '11',
                attributes: 'zoomfile="https://www.chiphell.com$url"',
              ) +
              attachmentImage('12') +
              attachmentImage('12') +
              attachmentImage('13'),
        ),
      ),
      tid: 42,
    ).posts.single;
    expect(imageUrls(post), [
      'https://www.chiphell.com$url',
      'https://www.chiphell.com$url',
      'https://example.invalid/12.jpg',
      'https://example.invalid/13.jpg',
    ]);
    expect(
      post.content
          .whereType<QuoteBlock>()
          .single
          .children
          .whereType<TextBlock>()
          .single
          .text,
      '合成引用',
    );
  });

  test('正文内部的附件不重复追加', () {
    final post = parseThread(
      attachmentPost(
        1,
        body: attachment(attachmentImage('1')),
        extra: attachment(attachmentImage('1')),
      ),
      tid: 42,
    ).posts.single;
    expect(imageUrls(post), ['https://example.invalid/1.jpg']);
  });

  test('复用懒加载URL优先级及相对地址标准化', () {
    final post = parseThread(
      attachmentPost(
        1,
        extra: attachment(
          attachmentImage(
                '1',
                attributes:
                    'zoomfile="/original.jpg" file="/file.jpg" data-src="/data.jpg" src="static/image/common/none.gif" width="640" height="480"',
              ) +
              attachmentImage(
                '2',
                attributes:
                    'file="/file.jpg" data-src="/data.jpg" src="static/image/common/none.gif"',
              ) +
              attachmentImage(
                '3',
                attributes:
                    'data-src="/data.jpg" data-original="/fallback.jpg"',
              ) +
              attachmentImage(
                '4',
                attributes:
                    'data-original="/fallback.jpg" src="static/image/common/none.gif"',
              ) +
              attachmentImage(
                '5',
                attributes: 'src="//example.invalid/source.jpg"',
              ),
        ),
      ),
      tid: 42,
    ).posts.single;
    expect(imageUrls(post), [
      'https://www.chiphell.com/original.jpg',
      'https://www.chiphell.com/file.jpg',
      'https://www.chiphell.com/data.jpg',
      'https://www.chiphell.com/fallback.jpg',
      'https://example.invalid/source.jpg',
    ]);
  });

  test('无正文也能读取附件，空楼不取邻楼附件', () {
    final posts = parseThread(
      attachmentPost(1, body: null) +
          attachmentPost(
            2,
            body: null,
            extra: attachment(attachmentImage('2')),
          ),
      tid: 42,
    ).posts;
    expect(posts[0].content, isEmpty);
    expect(imageUrls(posts[1]), ['https://example.invalid/2.jpg']);
    expect(posts[1].lock, isNull);
  });

  test('嵌套楼层附件不会合入父楼层', () {
    final posts = parseThread(
      attachmentPost(
        1,
        extra: attachmentPost(2, extra: attachment(attachmentImage('2'))),
      ),
      tid: 42,
    ).posts;
    expect(imageUrls(posts[0]), isEmpty);
    expect(imageUrls(posts[1]), ['https://example.invalid/2.jpg']);
  });

  test('头像勋章签名评分点评引用和下载图标不进入新增附件', () {
    final pollution = [
      for (final cls in ['avatar', 'medal', 'sign', 'rate', 'cm', 'quote'])
        '<div class="$cls">${attachment(attachmentImage(cls))}</div>',
      '<blockquote>${attachment(attachmentImage('quoted'))}</blockquote>',
      '<div class="pattl"><dl class="tattl"><dd><img src="static/image/filetype/zip.gif"><a href="forum.php?mod=attachment&amp;aid=1">合成.zip</a></dd></dl></div>',
    ].join();
    final post = parseThread(
      attachmentPost(
        1,
        extra:
            pollution +
            attachment(
              attachmentImage(
                    'icon',
                    attributes: 'src="static/image/common/none.gif"',
                  ) +
                  attachmentImage(
                    'zip',
                    attributes: 'src="static/image/filetype/zip.gif"',
                  ) +
                  attachmentImage(
                    'smiley',
                    attributes: 'src="static/image/smiley/default/smile.gif"',
                  ) +
                  attachmentImage('good'),
            ),
        outside: pollution,
      ),
      tid: 42,
    ).posts.single;
    expect(imageUrls(post), ['https://example.invalid/good.jpg']);
    expect(post.content.whereType<TextBlock>().map((b) => b.text), ['合成正文']);
  });

  for (final boundary in [
    'class="locked"',
    'class="attach_nopermission"',
    'class="attach_tips"',
    'class="aimg_tip"',
    'style="display: none"',
    'style="DISPLAY: none !important"',
    'style="visibility: hidden"',
    'hidden',
    'aria-hidden="true"',
  ]) {
    test('跳过受限或隐藏附件祖先：$boundary', () {
      final post = parseThread(
        attachmentPost(
          1,
          extra: attachment(
            '<div $boundary>${attachmentImage('hidden')}</div>${attachmentImage('visible')}',
          ),
        ),
        tid: 42,
      ).posts.single;
      expect(imageUrls(post), ['https://example.invalid/visible.jpg']);
    });
  }

  test('附件自身及整个附件容器隐藏时不补图', () {
    final post = parseThread(
      attachmentPost(
        1,
        extra:
            attachment(
              attachmentImage(
                'hidden',
                attributes: 'hidden src="https://example.invalid/hidden.jpg"',
              ),
            ) +
            attachment(attachmentImage('ancestor')).replaceFirst(
              'class="pattl"',
              'class="pattl" style="display:none"',
            ),
      ),
      tid: 42,
    ).posts.single;
    expect(imageUrls(post), isEmpty);
  });

  test('密码锁定楼层不会被正文外附件绕过', () {
    final post = parseThread(
      attachmentPost(
        1,
        body: null,
        extra:
            '<div class="locked">请输入密码<input id="postpw_1"></div>${attachment(attachmentImage('1'))}',
      ),
      tid: 42,
    ).posts.single;
    expect(post.lock?.needsPassword, isTrue);
    expect(post.content, isEmpty);
  });

  test('正文内局部权限提示不影响其他公开附件', () {
    final post = parseThread(
      attachmentPost(
        1,
        body: '<div class="locked">登录可见${attachmentImage('private')}</div>',
        extra: attachment(attachmentImage('public')),
      ),
      tid: 42,
    ).posts.single;
    expect(post.lock, isNull);
    expect(post.content.whereType<QuoteBlock>().single.isNotice, isTrue);
    expect(imageUrls(post), ['https://example.invalid/public.jpg']);
  });
}
