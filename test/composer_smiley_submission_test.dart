import 'dart:io';

import 'package:chh_app/data/message_repository.dart';
import 'package:chh_app/data/post_interaction_drafts.dart';
import 'package:chh_app/data/post_interaction_repository.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/di.dart';
import 'package:chh_app/models/article_discussion.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/models/post_interaction.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:chh_app/pages/article_discussion_page.dart';
import 'package:chh_app/pages/pm_thread_page.dart';
import 'package:chh_app/pages/thread_detail_page.dart';
import 'package:chh_app/widgets/composer/composer_tool_strip.dart';
import 'package:chh_app/widgets/post_interaction_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'article_discussion_test.dart' show form;
import 'messages_ui_test.dart' show pmFixture;
import 'post_interaction_test.dart' show commentForm, pid, tid;

import 'support/inline_forum_parser.dart';

const _body = '段首 :)\n段尾 :(';
const _composerSend = ValueKey('composer-send');

class _FormTransport extends ChhFetcher {
  _FormTransport(this.html);

  final String html;
  final posts = <({Uri url, Map<String, String> fields})>[];

  @override
  String get name => 'fake-smiley-form';

  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) async =>
      ChhResponse(200, html);

  @override
  Future<ChhResponse> postForm(Uri url, Map<String, String> form) async {
    posts.add((url: url, fields: Map.of(form)));
    return const ChhResponse(200, '<div id="messagetext">离线测试结果</div>');
  }
}

void _replaceDefaultTransport(_FormTransport transport) {
  useInlineForumParser(chhClient);
  final original = List.of(chhClient.fetchers);
  chhClient.clearCache();
  chhClient.fetchers
    ..clear()
    ..add(transport);
  addTearDown(() {
    chhClient.clearCache();
    chhClient.fetchers
      ..clear()
      ..addAll(original);
  });
}

Future<void> _open(WidgetTester tester, Widget home) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(theme: buildAppTheme(Brightness.light), home: home),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField), _body);
  await tester.pump();
}

void main() {
  testWidgets('reply draft restores raw smiley codes and posts them', (
    tester,
  ) async {
    final transport = _FormTransport(
      File('test_data/thread_synthetic.html').readAsStringSync(),
    );
    _replaceDefaultTransport(transport);
    await _open(tester, const ThreadDetailPage(tid: 900001, title: '合成样本'));
    final reply = find.text('写回复…');
    await _tap(tester, reply);
    expect(find.byType(ComposerEmojiTool), findsOneWidget);
    await _enter(tester);
    await _tap(tester, find.text('取消'));
    expect(transport.posts, isEmpty);
    await _tap(tester, reply);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      _body,
    );
    await _tap(tester, find.byKey(_composerSend));
    expect(transport.posts.single.url.queryParameters['action'], 'reply');
    expect(transport.posts.single.fields['message'], _body);
  });

  testWidgets('portal comment posts raw smiley codes', (tester) async {
    final transport = _FormTransport(form());
    _replaceDefaultTransport(transport);
    await _open(
      tester,
      ArticleDiscussionPage(
        aid: 50001,
        title: '合成文章',
        isLoggedIn: () => true,
        loadPage: (_, _) async => const ArticleDiscussion(
          aid: 50001,
          title: '合成文章',
          items: [],
          page: PageInfo(current: 1, hasNext: false),
        ),
      ),
    );
    await _tap(tester, find.byKey(const ValueKey('discussion-write-action')));
    expect(find.byType(ComposerEmojiTool), findsNothing);
    await _enter(tester);
    await _tap(tester, find.byKey(_composerSend));
    expect(transport.posts.single.url.queryParameters['ac'], 'comment');
    expect(transport.posts.single.fields['message'], _body);
  });

  testWidgets('private message posts raw smiley codes', (tester) async {
    final transport = _FormTransport('''
<div id="pm_ul"></div>
<form id="pmform" method="post"
 action="home.php?mod=spacecp&amp;ac=pm&amp;op=send&amp;pmid=60001&amp;pmsubmit=yes">
  <input type="hidden" name="formhash" value="synthetic-formhash">
  <input type="hidden" name="topmuid" value="100002">
  <textarea name="message"></textarea>
</form>''');
    await _open(
      tester,
      PmThreadPage(
        conversation: pmFixture,
        repository: MessageRepository(ChhClient(fetchers: [transport])),
      ),
    );
    expect(find.byType(ComposerEmojiTool), findsOneWidget);
    await _enter(tester);
    await _tap(tester, find.byKey(const ValueKey('pm-send')));
    expect(transport.posts.single.url.queryParameters['pmsubmit'], 'yes');
    expect(transport.posts.single.fields['message'], _body);
  });

  for (final kind in [
    PostInteractionKind.comment,
    PostInteractionKind.supplement,
  ]) {
    final supplement = kind == PostInteractionKind.supplement;
    testWidgets('${kind.name} posts raw smiley codes', (tester) async {
      final transport = _FormTransport(
        supplement
            ? '''
<form action="forum.php?mod=misc&amp;action=postappend&amp;tid=$tid&amp;pid=$pid">
  <input type="hidden" name="formhash" value="synthetic-formhash">
  <textarea name="postappendmessage"></textarea>
</form>'''
            : commentForm(),
      );
      final repository = PostInteractionRepository(
        ChhClient(fetchers: [transport]),
        sessionIdentity: () => 'tester',
      );
      await _open(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showPostInteractionSheet(
                context,
                kind: kind,
                tid: tid,
                post: const Post(
                  pid: pid,
                  floor: 2,
                  author: '离线作者',
                  timeRaw: '',
                  content: [],
                ),
                repository: repository,
                sessionIdentity: () => 'tester',
                drafts: PostInteractionDraftStore(),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      );
      await _tap(tester, find.text('打开'));
      expect(find.byType(ComposerEmojiTool), findsNothing);
      await _enter(tester);
      await _tap(tester, find.byKey(const ValueKey('interaction-send')));
      final post = transport.posts.single;
      expect(
        post.url.queryParameters[supplement
            ? 'postappendsubmit'
            : 'commentsubmit'],
        'yes',
      );
      expect(post.fields[supplement ? 'postappendmessage' : 'message'], _body);
    });
  }
}
