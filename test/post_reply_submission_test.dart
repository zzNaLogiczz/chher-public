/// Request-level regression fixtures; no requests reach the forum.
library;

import 'dart:convert';

import 'package:chh_app/data/post_repository.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';

const _quote =
    '[quote][url=forum.php?mod=redirect&goto=findpost&pid=3&ptid=123]'
    '用户B 发表于 2026-10-26 10:00[/url]\nB 的正文[/quote]';

class _Transport extends ChhFetcher {
  String form;
  final gets = <Uri>[];
  final posts = <({Uri url, Map<String, String> fields})>[];
  _Transport(this.form);

  @override
  String get name => 'fake';

  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) async {
    gets.add(url);
    return ChhResponse(200, form);
  }

  @override
  Future<ChhResponse> postForm(Uri url, Map<String, String> form) async {
    posts.add((url: url, fields: Map.of(form)));
    return const ChhResponse(302, '');
  }
}

String _form(String controls, {bool quick = false}) =>
    '''
<form id="${quick ? 'fastpostform' : 'postform'}"
 action="forum.php?mod=post&amp;action=reply&amp;tid=123&amp;replysubmit=yes">
<input type="hidden" name="formhash" value="fresh-hash">
<input type="hidden" name="reppid" value="3">
<input type="hidden" name="noticeauthor" value="server-notice-token">
$controls</form>''';

void main() {
  for (final tag in ['input', 'textarea']) {
    test(
      'quote in $tag survives actual submission without duplication',
      () async {
        final encoded = const HtmlEscape().convert(_quote);
        final transport = _Transport(
          _form(
            tag == 'input'
                ? '<input type="hidden" name="noticetrimstr" value="$encoded">'
                : '<textarea name="noticetrimstr" style="display:none">$encoded</textarea>',
          ),
        );
        final repository = PostRepository(ChhClient(fetchers: [transport]));
        final result = await repository.reply(
          tid: 123,
          fid: 290,
          quotePid: 3,
          page: 4,
          message: 'C 的回复',
        );
        expect(result.isSuccess, isTrue);
        expect(transport.gets.single.queryParameters['repquote'], '3');
        expect(transport.gets.single.queryParameters['page'], '4');
        final fields = transport.posts.single.fields;
        expect(fields['noticetrimstr'], _quote);
        expect(fields['noticeauthor'], 'server-notice-token');
        expect(fields['reppid'], '3');
        expect(fields['formhash'], 'fresh-hash');
        expect(fields['message'], 'C 的回复');
      },
    );
  }

  test('prefilled message quotation is kept before the user reply', () async {
    final transport = _Transport(
      _form(
        '<textarea name="message">${const HtmlEscape().convert(_quote)}</textarea>',
      ),
    );
    final repository = PostRepository(ChhClient(fetchers: [transport]));
    await repository.reply(tid: 123, fid: 290, quotePid: 3, message: 'C 的回复');
    expect(transport.posts.single.fields['message'], '$_quote\n\nC 的回复');
  });

  test(
    'missing quote context never silently submits an independent reply',
    () async {
      final transport = _Transport(
        _form('<textarea name="message"></textarea>'),
      );
      final result = await PostRepository(
        ChhClient(fetchers: [transport]),
      ).reply(tid: 123, fid: 290, quotePid: 3, message: '保留在草稿里的回复');
      expect(result.isSuccess, isFalse);
      expect(transport.posts, isEmpty);
    },
  );

  test('ordinary reply sends only entered text', () async {
    final transport = _Transport(
      _form('<textarea name="message">站点草稿</textarea>', quick: true),
    );
    await PostRepository(
      ChhClient(fetchers: [transport]),
    ).reply(tid: 123, fid: 290, page: 2, message: '独立评论');
    expect(transport.posts.single.fields['message'], '独立评论');
  });
}
