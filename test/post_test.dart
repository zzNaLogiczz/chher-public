/// 发帖与回帖解析单测
///
/// 不对站点提交任何内容:这里只断言表单抽取与响应判定的结构契约。
/// 真实提交由用户在真机上主动触发。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:chh_app/models/models.dart';
import 'package:chh_app/parser/pm_parser.dart';
import 'package:chh_app/parser/post_form_parser.dart';

String _page(String body) =>
    '<html><head><title>页面</title></head><body>$body</body></html>';

void main() {
  group('快速回复表单', () {
    final html = _page('''
<div id="ct">
  <form id="fastpostform" method="post"
        action="forum.php?mod=post&amp;action=reply&amp;fid=290&amp;tid=900101&amp;extra=&amp;replysubmit=yes&amp;infloat=yes&amp;handlekey=fastpost">
    <input type="hidden" name="formhash" value="synthetic-reply-formhash">
    <input type="hidden" name="posttime" value="978307200">
    <input type="hidden" name="usesig" value="1">
    <input type="hidden" name="subject" value="">
    <textarea id="fastpostmessage" name="message"></textarea>
  </form>
</div>''');

    test('抽出 action 与 formhash', () {
      final form = parseFastReplyForm(html)!;
      expect(form.formhash, 'synthetic-reply-formhash');
      expect(form.action, contains('replysubmit=yes'));
      expect(form.action, startsWith('https://'));
    });

    test('隐藏字段原样保留,formhash 单独拿出不混进去', () {
      final form = parseFastReplyForm(html)!;
      expect(form.hidden['posttime'], '978307200');
      expect(form.hidden['usesig'], '1');
      expect(form.hidden.containsKey('formhash'), isFalse);
    });

    test('快速回复不需要标题', () {
      expect(parseFastReplyForm(html)!.requiresSubject, isFalse);
    });

    test('没有表单说明当前不可回复', () {
      expect(parseFastReplyForm(_page('<div id="ct">正文</div>')), isNull);
    });

    test('登录墙先抛消息,不返回空表单', () {
      expect(
        () => parseFastReplyForm(
          _page(
            '<div id="messagetext">请先登录</div><div id="messagelogin"></div>',
          ),
        ),
        throwsA(isA<PageMessage>()),
      );
    });
  });

  group('高级发帖表单', () {
    test('#postform 在 #ct 外层也要能找到', () {
      final form = parseAdvancedPostForm(
        _page('''
<form id="postform" method="post"
      action="forum.php?mod=post&amp;action=newthread&amp;fid=290&amp;topicsubmit=yes">
  <input type="hidden" name="formhash" value="synthetic-post-formhash">
  <div id="ct">正文区在表单内部</div>
</form>'''),
      )!;
      expect(form.formhash, 'synthetic-post-formhash');
      expect(form.requiresSubject, isTrue);
    });

    test('发主题解析分类选项并识别默认选中', () {
      final form = parseAdvancedPostForm(
        _page('''
<form id="postform" action="forum.php?mod=post&amp;action=newthread&amp;fid=290&amp;topicsubmit=yes">
  <input type="hidden" name="formhash" value="synthetic-post-formhash">
  <select id="typeid" name="typeid">
    <option value="0">选择分类</option>
    <option value="1010">ITX</option>
    <option value="1011" selected>水冷</option>
  </select>
</form>'''),
      )!;
      expect(form.types.map((e) => e.typeid), [1010, 1011]);
      expect(form.types.last.active, isTrue);
    });

    test('引用回复不要求标题', () {
      final form = parseAdvancedPostForm(
        _page('''
<form id="postform" action="forum.php?mod=post&amp;action=reply&amp;fid=290&amp;tid=1&amp;repquote=555&amp;replysubmit=yes">
  <input type="hidden" name="formhash" value="synthetic-post-formhash">
  <input type="hidden" name="reppid" value="555">
</form>'''),
      )!;
      expect(form.requiresSubject, isFalse);
      expect(form.hidden['reppid'], '555');
    });

    test('出现验证码控件时标记出来', () {
      final form = parseAdvancedPostForm(
        _page('''
<form id="postform" action="forum.php?mod=post&amp;topicsubmit=yes">
  <input type="hidden" name="formhash" value="synthetic-post-formhash">
  <input type="text" name="seccodeverify">
</form>'''),
      )!;
      expect(form.hasCaptcha, isTrue);
    });

    test('脚本插入的腾讯滑块也算验证码:原始页面只有占位和加载脚本', () {
      final form = parseAdvancedPostForm(
        _page('''
<form id="postform" action="forum.php?mod=post&amp;action=newthread&amp;fid=2&amp;topicsubmit=yes">
  <input type="hidden" name="formhash" value="synthetic-post-formhash">
  <span id="seccode_syntheticCaptcha"></span>
  <script type="text/javascript" reload="1">updateseccode('syntheticCaptcha', '<sec> <sec>', 'forum::post');</script>
</form>'''),
      )!;
      expect(form.hasCaptcha, isTrue);
    });

    test('读出图片上传参数:hash、当前用户、大小上限与扩展名', () {
      final form = parseAdvancedPostForm(
        _page(
          '''
<div id="um"><strong class="vwmy"><a href="space-uid-123456.html">某用户</a></strong></div>
<form id="postform" action="forum.php?mod=post&amp;action=reply&amp;tid=1&amp;replysubmit=yes">
  <input type="hidden" name="formhash" value="synthetic-post-formhash">
  <input type="hidden" name="hash" value="upload-hash">
</form>
<script>var imgexts = 'jpg, jpeg,gif,png';
var upload = new SWFUpload({ file_size_limit : "2048", file_types : "*.jpg"});</script>''',
        ),
      )!;
      final upload = form.upload!;
      expect(upload.uid, '123456');
      expect(upload.hash, 'upload-hash');
      expect(upload.maxBytes, 2048 * 1024);
      expect(upload.extensions, {'jpg', 'jpeg', 'gif', 'png'});
    });

    test('游客页没有当前用户,不给半套上传参数', () {
      final form = parseAdvancedPostForm(
        _page('''
<form id="postform" action="forum.php?mod=post&amp;topicsubmit=yes">
  <input type="hidden" name="formhash" value="synthetic-post-formhash">
  <input type="hidden" name="hash" value="upload-hash">
</form>'''),
      )!;
      expect(form.upload, isNull);
    });

    test('缺 formhash 视为表单不可用', () {
      expect(
        parseAdvancedPostForm(
          _page(
            '<form id="postform" action="forum.php?mod=post&amp;topicsubmit=yes"></form>',
          ),
        ),
        isNull,
      );
    });
  });

  group('提交响应判定', () {
    test('跳回帖子页是最可靠的成功信号,并带出 tid 与 pid', () {
      final r = parsePostResult(
        '<script>location.href="forum.php?mod=viewthread&tid=900101&pid=99887";</script>',
      );
      expect(r.kind, PostResultKind.success);
      expect(r.tid, 900101);
      expect(r.pid, 99887);
    });

    test('提示页里的返回脚本不混进提示文字', () {
      final r = parsePostResult(
        _page('''
<div id="messagetext" class="alert_error"><p>抱歉，验证码填写错误</p>
<script type="text/javascript">if(history.length > (BROWSER.ie ? 0 : 1)) { document.write('<p class="alert_btnleft"><a href="javascript:history.back()">[ 点击这里返回上一页 ]</a></p>'); }</script>
</div>'''),
      );
      expect(r.kind, PostResultKind.needCaptcha);
      expect(r.message, '抱歉，验证码填写错误');
    });

    test('要求验证码单独成一类,不当普通失败', () {
      final r = parsePostResult(_page('<div id="messagetext">请输入正确的验证码</div>'));
      expect(r.kind, PostResultKind.needCaptcha);
    });

    test('发帖间隔限制归为节流,保留站点原文', () {
      final r = parsePostResult(
        _page('<div id="messagetext">两次发表间隔少于 30 秒</div>'),
      );
      expect(r.kind, PostResultKind.throttled);
      expect(r.message, contains('30 秒'));
    });

    test('权限不足与登录墙分开判', () {
      expect(
        parsePostResult(_page('<div id="messagetext">您没有权限回复</div>')).kind,
        PostResultKind.permissionDenied,
      );
      expect(
        parsePostResult(
          _page(
            '<div id="messagetext">请先登录</div><div id="messagelogin"></div>',
          ),
        ).kind,
        PostResultKind.loginRequired,
      );
    });

    test('判不出来就是 unknown,不假装成功', () {
      final r = parsePostResult(_page('<div>一段无法归类的响应</div>'));
      expect(r.kind, PostResultKind.unknown);
      expect(r.isSuccess, isFalse);
    });
  });

  _redirectResultTests();
}

/// 提交结果判定的回归
///
/// 合成响应场景：直连 POST 回帖成功时返回 301 空响应。
/// 曾经把「空响应」当成没被处理而换通道补发一次,结果撞上站点的 10 秒发表间隔。
void _redirectResultTests() {
  group('跳转形态的提交结果', () {
    test('3xx 空响应判为成功,不是未知', () {
      final r = parsePostResult('', status: 301);
      expect(r.kind, PostResultKind.success);
    });

    test('跟随跳转落在帖子页判为成功', () {
      final r = parsePostResult(
        '<html><body><div id="postlist">'
        '<td id="postmessage_123">正文</td></div></body></html>',
        status: 200,
      );
      expect(r.kind, PostResultKind.success);
    });

    test('落地页带提示信息时以提示为准,不当成功', () {
      final r = parsePostResult(
        '<html><body><div id="messagetext">'
        '<p>抱歉,您两次发表间隔少于 10 秒</p></div>'
        '<div id="postlist"></div></body></html>',
        status: 200,
      );
      expect(r.kind, PostResultKind.throttled);
    });

    test('200 空响应不算成功,只有跳转才算', () {
      expect(parsePostResult('', status: 200).kind, PostResultKind.unknown);
    });
  });

  _pmReplyFormTests();
}

/// 私信回复表单
///
/// 合成结构：pmid 在 action 里,表单只有 message / formhash / topmuid,
/// 没有文档里推测的 touid 字段。
void _pmReplyFormTests() {
  group('私信回复表单', () {
    const synthetic = '''
<form id="pmform" method="post"
      action="home.php?mod=spacecp&amp;ac=pm&amp;op=send&amp;pmid=60001&amp;daterange=0&amp;handlekey=pmsend&amp;pmsubmit=yes">
  <textarea id="replymessage" name="message"></textarea>
  <input type="hidden" name="formhash" value="synthetic-formhash">
  <input type="hidden" name="topmuid" value="100002">
</form>''';

    test('照搬站点 action,pmid 不自己拼', () {
      final f = parsePmReplyForm(_page(synthetic))!;
      expect(f.action, contains('pmid=60001'));
      expect(f.action, contains('pmsubmit=yes'));
      expect(f.action, startsWith('https://'));
    });

    test('formhash 单独取出,topmuid 留在隐藏字段里原样回传', () {
      final f = parsePmReplyForm(_page(synthetic))!;
      expect(f.formhash, 'synthetic-formhash');
      expect(f.hidden['topmuid'], '100002');
      expect(f.hidden.containsKey('formhash'), isFalse);
    });

    test('没有表单说明这个会话不可回复', () {
      expect(parsePmReplyForm(_page('<div id="pm_ul"></div>')), isNull);
    });

    test('登录墙先抛消息', () {
      expect(
        () => parsePmReplyForm(
          _page(
            '<div id="messagetext">请先登录</div><div id="messagelogin"></div>',
          ),
        ),
        throwsA(isA<PageMessage>()),
      );
    });
  });
}
