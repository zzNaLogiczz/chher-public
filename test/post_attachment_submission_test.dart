/// 图片上传与需要人机验证的发布:请求级断言,不向论坛发送任何内容。
library;

import 'package:chh_app/data/post_repository.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:chh_app/parser/upload_parser.dart';
import 'package:flutter_test/flutter_test.dart';

class _Transport extends ChhFetcher {
  final String page;
  final ChhResponse postReply;
  final gets = <Uri>[];
  final posts = <({Uri url, Map<String, String> fields})>[];
  final uploads = <({Uri url, Map<String, String> fields, UploadFile file})>[];

  _Transport(this.page, {this.postReply = const ChhResponse(302, '')});

  @override
  String get name => 'fake';

  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) async {
    gets.add(url);
    return ChhResponse(200, page);
  }

  @override
  Future<ChhResponse> postForm(Uri url, Map<String, String> form) async {
    posts.add((url: url, fields: Map.of(form)));
    return postReply;
  }

  @override
  Future<ChhResponse> postMultipart(
    Uri url,
    Map<String, String> fields,
    UploadFile file,
  ) async {
    uploads.add((url: url, fields: Map.of(fields), file: file));
    return const ChhResponse(200, 'DISCUZUPLOAD|0|778899|1|0');
  }
}

String _postPage({bool captcha = false, String action = 'replysubmit=yes'}) =>
    '''
<html><body>
<div id="um"><strong class="vwmy"><a href="space-uid-42.html">我</a></strong></div>
<form id="postform" action="forum.php?mod=post&amp;fid=7&amp;tid=123&amp;$action">
  <input type="hidden" name="formhash" value="fresh-formhash">
  <input type="hidden" name="posttime" value="1792800000">
  <input type="hidden" name="wysiwyg" id="e_mode" value="1">
  <input type="hidden" name="hash" value="upload-hash">
  ${captcha ? '<span id="seccode_cSx"></span><script>updateseccode(\'cSx\', \'\', \'forum::post\');</script>' : ''}
  <textarea name="message"></textarea>
</form>
<script>var upload = {file_size_limit : "1024"};</script>
</body></html>''';

void main() {
  group('上传回包', () {
    test('DISCUZUPLOAD 状态 0 返回附件编号', () {
      final r = parseUploadResponse('DISCUZUPLOAD|0|123456|1|0');
      expect((r as UploadSucceeded).aid, '123456');
    });

    test('状态非 0 是失败,不继续猜其他格式', () {
      expect(
        parseUploadResponse('DISCUZUPLOAD|2|123456|0'),
        isA<UploadFailed>(),
      );
    });

    test('附件编号 0 不能当成功', () {
      expect(parseUploadResponse('DISCUZ_UPLOAD|0|0|0'), isA<UploadFailed>());
    });

    test('JSON 形态的 aid 也认', () {
      final r = parseUploadResponse('{"aid":"55"}');
      expect((r as UploadSucceeded).aid, '55');
    });

    test('413 与提示页给出可读原因,不带脚本', () {
      expect(
        (parseUploadResponse('', status: 413) as UploadFailed).message,
        contains('大小'),
      );
      final page = parseUploadResponse(
        '<div id="messagetext"><p>您今天上传的附件已达上限</p><script>history.back()</script></div>',
      );
      expect((page as UploadFailed).message, '图片上传失败：您今天上传的附件已达上限');
    });
  });

  test('上传请求带上表单页给的 uid 与 hash,文件项名为 Filedata', () async {
    final transport = _Transport(_postPage());
    final repo = PostRepository(ChhClient(fetchers: [transport]));
    final context = (await repo.replyUploadContext(tid: 123, fid: 7))!;
    expect(context.maxBytes, 1024 * 1024);

    final outcome = await repo.uploadImage(
      context,
      bytes: const [1, 2, 3],
      filename: 'image_1.jpg',
      contentType: 'image/jpeg',
    );
    expect((outcome as UploadSucceeded).aid, '778899');
    final upload = transport.uploads.single;
    expect(upload.url.path, '/misc.php');
    expect(upload.url.queryParameters, {
      'mod': 'swfupload',
      'operation': 'upload',
      'uid': '42',
      'hash': 'upload-hash',
      'simple': '1',
      'type': 'image',
    });
    expect(upload.fields, {'uid': '42', 'hash': 'upload-hash'});
    expect(upload.file.field, 'Filedata');
    expect(upload.file.filename, 'image_1.jpg');
    expect(transport.posts, isEmpty);
  });

  test('带图回复走完整回复表单,正文末尾接附件标记并声明附件', () async {
    final transport = _Transport(_postPage());
    final repo = PostRepository(ChhClient(fetchers: [transport]));
    final result = await repo.reply(
      tid: 123,
      fid: 7,
      message: '看图',
      images: const ['11', '22'],
    );
    expect(result.isSuccess, isTrue);
    expect(transport.gets.single.queryParameters['action'], 'reply');
    expect(
      transport.gets.single.queryParameters.containsKey('repquote'),
      isFalse,
    );
    final fields = transport.posts.single.fields;
    expect(
      fields['message'],
      '看图\n\n[attachimg]11[/attachimg]\n[attachimg]22[/attachimg]',
    );
    expect(fields['attachnew[11][description]'], '');
    expect(fields['attachnew[22][description]'], '');
    // 正文是纯文本 BBCode,不能让站点按所见即所得 HTML 转换
    expect(fields['wysiwyg'], '0');
    expect(fields['formhash'], 'fresh-formhash');
  });

  test('只有图片也能发主题', () async {
    final transport = _Transport(_postPage(action: 'topicsubmit=yes'));
    final repo = PostRepository(ChhClient(fetchers: [transport]));
    await repo.createThread(
      fid: 7,
      subject: '标题',
      message: '',
      images: const ['9'],
    );
    final fields = transport.posts.single.fields;
    expect(fields['message'], '[attachimg]9[/attachimg]');
    expect(fields['subject'], '标题');
    expect(fields['topicsubmit'], 'yes');
  });

  test('表单需要人机验证时不直连提交,把要填的字段交给站点页面', () async {
    final transport = _Transport(
      _postPage(captcha: true, action: 'topicsubmit=yes'),
    );
    final repo = PostRepository(ChhClient(fetchers: [transport]));
    final result = await repo.createThread(
      fid: 7,
      subject: '京东减脂餐',
      message: '正文',
      typeid: 3,
      images: const ['9'],
    );
    expect(transport.posts, isEmpty);
    expect(result.kind, PostResultKind.needCaptcha);
    final web = result.web!;
    expect(web.page.queryParameters['action'], 'newthread');
    expect(web.page.queryParameters['fid'], '7');
    expect(web.fields['subject'], '京东减脂餐');
    expect(web.fields['message'], '正文\n\n[attachimg]9[/attachimg]');
    expect(web.fields['typeid'], '3');
    expect(web.fields['attachnew[9][description]'], '');
    // 表单令牌由站点页面自己带,不把旧的 formhash 塞进去
    expect(web.fields.containsKey('formhash'), isFalse);
  });

  test('没认出验证码、站点却回验证码错误:同样改到站点页面完成', () async {
    // 帖子页的快速回复表单
    final transport = _Transport(
      _postPage().replaceFirst('id="postform"', 'id="fastpostform"'),
      postReply: const ChhResponse(
        200,
        '<div id="messagetext"><p>抱歉，验证码填写错误</p></div>',
      ),
    );
    final repo = PostRepository(ChhClient(fetchers: [transport]));
    final result = await repo.reply(tid: 123, fid: 7, message: '回复');
    expect(result.kind, PostResultKind.needCaptcha);
    expect(result.message, '抱歉，验证码填写错误');
    expect(result.web!.fields['message'], '回复');
    expect(result.web!.page.queryParameters['action'], 'reply');
  });
}
