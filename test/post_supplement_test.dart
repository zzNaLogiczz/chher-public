import 'dart:async';
import 'package:chh_app/data/post_interaction_repository.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/models/post_interaction.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:chh_app/parser/post_action_parser.dart';
import 'package:chh_app/widgets/post_action_menu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html;
import 'post_interaction_test.dart' as fixture;
import 'post_action_menu_test.dart' as menu;

String form([String hash = 'fresh']) =>
    '''<root><![CDATA[
<form id="postappendform" action="forum.php?mod=misc&action=postappend&tid=10&pid=20&postappendsubmit=yes&infloat=yes">
<input type="hidden" name="formhash" value="$hash"><input type="hidden" name="custom" value="retained">
<textarea name="postappendmessage"></textarea><strong id="checklen_append">200</strong>
</form>]]></root>''';
const success =
    '<root><![CDATA[<script>succeedhandle_postappend("", "添加成功 ", {});</script>]]></root>';
PostSupplementForm parse(String raw) => parsePostSupplementForm(
  raw,
  tid: 10,
  pid: 20,
  pageUrl: supplementPageUrl(10, 20),
  sessionIdentity: 'actor',
  sessionRevision: 1,
)!;

void main() {
  test('source append form retains server fields and visible maximum', () {
    final f = parse(form());
    expect(f.maxLength, 200);
    expect(f.hidden['custom'], 'retained');
    expect(f.formhash, 'fresh');
    expect(parsePostSupplementResult(success).isSuccess, isTrue);
    expect(
      parsePostSupplementResult('<html>未确认</html>').kind,
      PostResultKind.unknown,
    );
    expect(
      parsePostSupplementResult(success, status: 500).kind,
      PostResultKind.unknown,
    );
  });
  test('rejects foreign actions, wrong posts, captcha and missing fields', () {
    for (final raw in [
      form().replaceAll('forum.php?', 'https://evil.invalid/forum.php?'),
      form().replaceAll('pid=20', 'pid=21'),
      form().replaceAll('formhash', 'other'),
      form().replaceAll('postappendmessage', 'message'),
      form().replaceAll('</form>', '<input name="seccodeverify"></form>'),
    ]) {
      expect(
        parsePostSupplementForm(
          raw,
          tid: 10,
          pid: 20,
          pageUrl: supplementPageUrl(10, 20),
          sessionIdentity: 'actor',
        ),
        isNull,
      );
    }
    expect(
      isSupplementUrl(Uri.parse('${supplementPageUrl(10, 20)}&pid=21'), 10, 20),
      isFalse,
    );
  });
  test('observes append toolbar links without accepting body links', () {
    final table = html
        .parse(
          '<table id="pid20"><tr><td><div id="postmessage_20"><a href="${supplementPageUrl(10, 20)}">补充</a></div></td></tr></table>',
        )
        .getElementById('pid20')!;
    expect(
      parsePostActionCapabilities(table, tid: 10, pid: 20).supplementUrl,
      isNull,
    );
    final toolbar = html
        .parse(
          '<table id="pid20"><tr><td><div class="po"><a href="${supplementPageUrl(10, 20)}">补充</a></div></td></tr></table>',
        )
        .getElementById('pid20')!;
    expect(
      parsePostActionCapabilities(toolbar, tid: 10, pid: 20).supplementUrl,
      isNotNull,
    );
  });
  test(
    'submission rereads hash, sends append fields once and keeps original body separate',
    () async {
      var reads = 0;
      final fake = fixture.Fake(
        onGet: (_) => ChhResponse(200, form('hash${++reads}')),
        onPost: (_, _) => const ChhResponse(200, success),
      );
      final repo = PostInteractionRepository(
        ChhClient(fetchers: [fake]),
        sessionIdentity: () => 'actor',
        sessionRevision: () => 1,
      );
      final f = await repo.supplementForm(tid: 10, pid: 20);
      expect(
        (await repo.submitSupplement(form: f, message: '新增内容')).isSuccess,
        isTrue,
      );
      expect(reads, 2);
      expect(fake.posts, hasLength(1));
      expect(fake.posts.single.fields['formhash'], 'hash2');
      expect(fake.posts.single.fields['postappendmessage'], '新增内容');
      expect(fake.posts.single.fields.containsKey('message'), isFalse);
      expect(fake.posts.single.url.queryParameters['postappendsubmit'], 'yes');
    },
  );
  test(
    'blocks stale account, changed limits and duplicate submissions',
    () async {
      var actor = 'actor';
      final pending = Completer<ChhResponse>();
      final fake = fixture.Fake(
        onGet: (_) => ChhResponse(200, form()),
        onPost: (_, _) => pending.future,
      );
      final repo = PostInteractionRepository(
        ChhClient(fetchers: [fake]),
        sessionIdentity: () => actor,
        sessionRevision: () => 1,
      );
      final f = await repo.supplementForm(tid: 10, pid: 20);
      actor = 'other';
      expect(
        (await repo.submitSupplement(form: f, message: 'text')).kind,
        PostResultKind.loginRequired,
      );
      expect(fake.posts, isEmpty);
      actor = 'actor';
      expect(
        (await repo.submitSupplement(form: f, message: 'x' * 201)).isSuccess,
        isFalse,
      );
      expect(fake.posts, isEmpty);
      final first = repo.submitSupplement(form: f, message: 'text');
      expect(
        (await repo.submitSupplement(form: f, message: 'text')).isSuccess,
        isFalse,
      );
      pending.complete(const ChhResponse(200, success));
      expect((await first).isSuccess, isTrue);
      expect(fake.posts, hasLength(1));
    },
  );
  test('ambiguous POST is unknown and never automatically retried', () async {
    final fake = fixture.Fake(
      onGet: (_) => ChhResponse(200, form()),
      onPost: (_, _) => const ChhResponse(0, ''),
    );
    final repo = PostInteractionRepository(
      ChhClient(fetchers: [fake]),
      sessionIdentity: () => 'actor',
      sessionRevision: () => 1,
    );
    expect(
      (await repo.submitSupplement(
        form: await repo.supplementForm(tid: 10, pid: 20),
        message: 'text',
      )).kind,
      PostResultKind.unknown,
    );
    expect(fake.posts, hasLength(1));
  });
  testWidgets('owned posts expose supplement and other posts do not', (
    tester,
  ) async {
    await menu.openMenu(tester, check: () async => menu.form(), isSelf: false);
    expect(find.text('补充'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    PostMenuAction? selected;
    await menu.openMenu(
      tester,
      check: () async => menu.form(),
      isSelf: true,
      selected: (value) => selected = value,
    );
    expect(find.text('补充'), findsOneWidget);
    await tester.tap(find.text('补充'));
    await tester.pumpAndSettle();
    expect(selected, PostMenuAction.supplement);
  });
}
