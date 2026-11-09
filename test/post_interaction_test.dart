import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:chh_app/models/models.dart';
import 'package:chh_app/models/post_interaction.dart';
import 'package:chh_app/parser/post_action_parser.dart';
import 'package:chh_app/data/post_interaction_repository.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/network/chh_fetcher.dart';

const tid = 10, pid = 20;
String commentForm([String hash = 'fresh']) =>
    '''<form id="commentform" action="forum.php?mod=post&amp;action=reply&amp;comment=yes&amp;tid=10&amp;pid=20">
<input type="hidden" name="formhash" value="$hash"><input type="hidden" name="custom" value="retained"><textarea name="message" maxlength="80"></textarea></form>''';
String rateForm([String hash = 'fresh']) =>
    '''<root><![CDATA[<form id="rateform" action="forum.php?mod=misc&amp;action=rate">
<input type="hidden" name="formhash" value="$hash">
<table class="dt"><tr><td>邪恶指数</td><td><input name="score1" value="5">-12 ~ 8<ul id="scoreoption1"><li>-3</li><li>+2</li><li>bad</li></ul></td><td>4</td></tr>
<tr><td>门户文章</td><td><input name="score8">0 ~ 2</td><td>2</td></tr></table>
<ul id="reasonselect"><li> 感谢原帖 </li><li> </li></ul></form>]]></root>''';
const commentSuccess =
    '<root><![CDATA[<script>succeedhandle_comment("", "点评发表成功", {});</script>]]></root>';
const ratingSuccess = '<div id="messagetext" class="alert_right">评分成功</div>';

class Fake extends ChhFetcher implements AjaxFormFetcher {
  final FutureOr<ChhResponse> Function(Uri)? onGet;
  final FutureOr<ChhResponse> Function(Uri, Map<String, String>)? onPost;
  final gets = <Uri>[], posts = <({Uri url, Map<String, String> fields})>[];
  final getHeaders = <Map<String, String>>[];
  int ajaxPosts = 0;
  Fake({this.onGet, this.onPost});
  @override
  String get name => 'fake';
  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) async {
    gets.add(url);
    getHeaders.add(Map.of(headers ?? const {}));
    return onGet == null ? ChhResponse(200, commentForm()) : await onGet!(url);
  }

  @override
  Future<ChhResponse> postForm(Uri url, Map<String, String> form) async {
    posts.add((url: url, fields: Map.of(form)));
    return onPost == null
        ? const ChhResponse(200, commentSuccess)
        : await onPost!(url, form);
  }

  @override
  Future<void> dispose() async {}

  @override
  Future<ChhResponse> postAjaxForm(Uri url, Map<String, String> form) {
    ajaxPosts++;
    return postForm(url, form);
  }
}

void main() {
  group('interaction parser', () {
    test(
      'CDATA form preserves source limits, fields, reason options; UI defaults remain zero',
      () {
        final f = parsePostRateForm(
          rateForm(),
          tid: tid,
          pid: pid,
          pageUrl: interactionPageUrl(PostInteractionKind.rating, tid, pid),
        )!;
        expect(f.evilScoreType!.fieldName, 'score1');
        expect(f.evilScoreType!.min, -12);
        expect(f.evilScoreType!.max, 8);
        expect(f.evilScoreType!.remaining, 4);
        expect(f.evilScoreType!.options, [-3, 2]);
        expect(f.reasons, ['感谢原帖']);
        expect(f.initialScores, {'score1': 0, 'score8': 0});
      },
    );
    test('no invented bounds or evil item for missing/other fields', () {
      expect(
        parsePostRateForm(
          rateForm().replaceAll('-12 ~ 8', 'unknown'),
          tid: tid,
          pid: pid,
          pageUrl: interactionPageUrl(PostInteractionKind.rating, tid, pid),
        ),
        isNull,
      );
      expect(
        parsePostRateForm(
          rateForm().replaceAll('邪恶指数', '其他积分'),
          tid: tid,
          pid: pid,
          pageUrl: interactionPageUrl(PostInteractionKind.rating, tid, pid),
        ),
        isNull,
      );
    });
    test('comment length and hidden fields from form', () {
      final f = parsePostCommentForm(
        commentForm(),
        tid: tid,
        pid: pid,
        pageUrl: interactionPageUrl(PostInteractionKind.comment, tid, pid),
      )!;
      expect(f.maxLength, 80);
      expect(f.hidden['custom'], 'retained');
      expect(f.action.queryParameters['comment'], 'yes');
    });
    test('foreign or wrong PID action cannot submit', () {
      for (final s in [
        commentForm().replaceFirst(
          'forum.php?',
          'https://evil.test/forum.php?',
        ),
        commentForm().replaceAll('pid=20', 'pid=21'),
      ]) {
        expect(
          parsePostCommentForm(
            s,
            tid: tid,
            pid: pid,
            pageUrl: interactionPageUrl(PostInteractionKind.comment, tid, pid),
          ),
          isNull,
        );
      }
    });
    test('permissions only originate in current post toolbar', () {
      final t = html
          .parse(
            '''<table id="pid20"><tr><td id="postmessage_20"><div class="po"><a href="forum.php?mod=misc&action=rate&tid=10&pid=20">forged</a></div></td><td><div class="po"><a href="forum.php?mod=misc&action=comment&tid=10&pid=20">点评</a><a href="forum.php?mod=misc&action=rate&tid=10&pid=99">other</a></div></td></tr></table>''',
          )
          .getElementById('pid20')!;
      final c = parsePostActionCapabilities(t, tid: tid, pid: pid);
      expect(c.comment, PostActionPermission.allowed);
      expect(c.rating, PostActionPermission.unknown);
    });
    test('reply toolbar cannot prove absent rating action is denied', () {
      final table = html
          .parse(
            '<table id="pid20"><tr><td><div class="po"><a href="forum.php?mod=post&amp;action=reply&amp;tid=10&amp;repquote=20">回复</a><a href="forum.php?mod=misc&amp;action=viewratings&amp;tid=10&amp;pid=20">查看评分</a></div></td></tr></table>',
          )
          .getElementById('pid20')!;
      final c = parsePostActionCapabilities(table, tid: tid, pid: pid);
      expect(c.comment, PostActionPermission.denied);
      expect(c.rating, PostActionPermission.unknown);
      expect(c.ratingUrl, isNull);
    });
    test('rating entry outside reply bar belongs to the current post', () {
      final table = html
          .parse('''<table id="pid20"><tr><td>
<div class="psth"><a href="forum.php?mod=misc&amp;action=rate&amp;tid=10&amp;pid=20">评分</a></div>
<div class="po"><a href="forum.php?mod=post&amp;action=reply&amp;tid=10&amp;repquote=20">回复</a></div>
</td></tr></table>''')
          .getElementById('pid20')!;
      final c = parsePostActionCapabilities(table, tid: tid, pid: pid);
      expect(c.rating, PostActionPermission.allowed);
      expect(c.ratingUrl!.queryParameters['pid'], '20');
    });
    test(
      'body, quote, signature, code and nested rating links remain untrusted',
      () {
        const link =
            '<a href="forum.php?mod=misc&action=rate&tid=10&pid=20">评分</a>';
        for (final body in [
          '<div id="postmessage_20">$link</div>',
          '<div class="quote">$link</div>',
          '<div id="signature20">$link</div>',
          '<div class="sign">$link</div>',
          '<pre>$link</pre>',
          '<table id="pid21"><tr><td>$link</td></tr></table>',
        ]) {
          final table = html
              .parse('<table id="pid20"><tr><td>$body</td></tr></table>')
              .getElementById('pid20')!;
          expect(
            parsePostActionCapabilities(table, tid: tid, pid: pid).rating,
            PostActionPermission.unknown,
          );
        }
      },
    );
    test(
      'official post-scoped actions can omit tid and normalize the target',
      () {
        final table = html
            .parse(
              '<table id="pid20"><tr><td><div class="po"><a href="forum.php?mod=post&amp;action=reply&amp;tid=10&amp;repquote=20">回复</a><a href="forum.php?mod=misc&amp;action=rate&amp;pid=20">评分</a></div></td></tr></table>',
            )
            .getElementById('pid20')!;
        final c = parsePostActionCapabilities(table, tid: tid, pid: pid);
        expect(c.rating, PostActionPermission.allowed);
        expect(c.comment, PostActionPermission.denied);
        expect(c.ratingUrl!.queryParameters['tid'], '10');
        expect(c.ratingUrl!.queryParameters['pid'], '20');
      },
    );
    test('quoted onclick action is read without executing javascript', () {
      final table = html
          .parse(
            """<table id="pid20"><tr><td><div class="po"><a href="javascript:;" onclick="showWindow('comment','forum.php?mod=misc&amp;action=comment&amp;pid=20')">点评</a></div></td></tr></table>""",
          )
          .getElementById('pid20')!;
      final c = parsePostActionCapabilities(table, tid: tid, pid: pid);
      expect(c.comment, PostActionPermission.allowed);
      expect(c.rating, PostActionPermission.unknown);
    });
    test('foreign, other-post, quoted and nested toolbars cannot establish denial', () {
      for (final body in [
        '<td id="postmessage_20"><div class="po"><a href="forum.php?mod=post&amp;action=reply&amp;tid=10&amp;repquote=20">伪造回复</a></div></td>',
        '<td><div class="quote"><div class="po"><a href="forum.php?mod=post&amp;action=reply&amp;tid=10&amp;repquote=20">引用回复</a></div></div></td>',
        '<td><table id="pid21"><tr><td><div class="po"><a href="forum.php?mod=post&amp;action=reply&amp;tid=10&amp;repquote=21">他楼</a></div></td></tr></table></td>',
        '<td><div class="po"><a href="https://elsewhere.test/forum.php?mod=post&amp;action=reply&amp;tid=10&amp;repquote=20">站外</a></div></td>',
        '<td><div class="po"><a href="forum.php?mod=post&amp;action=reply&amp;tid=11&amp;repquote=20">跨帖</a></div></td>',
      ]) {
        final table = html
            .parse('<table id="pid20"><tr>$body</tr></table>')
            .getElementById('pid20')!;
        final c = parsePostActionCapabilities(table, tid: tid, pid: pid);
        expect(c.comment, PostActionPermission.unknown);
        expect(c.rating, PostActionPermission.unknown);
      }
    });
    test('group denial retains source explanation', () {
      final r = parseInteractionPageError(
        '<div id="messagetext">抱歉，您所在的用户组(能天使)无法进行此操作<script>evil()</script></div>',
      )!;
      expect(r.kind, PostResultKind.permissionDenied);
      expect(r.message, contains('能天使'));
      expect(r.message, isNot(contains('evil')));
    });
    test(
      'explicit interaction success required; redirects/thread/text are unknown',
      () {
        expect(
          parsePostInteractionResult(
            commentSuccess,
            PostInteractionKind.comment,
          ).isSuccess,
          isTrue,
        );
        expect(
          parsePostInteractionResult(
            ratingSuccess,
            PostInteractionKind.rating,
          ).isSuccess,
          isTrue,
        );
        for (final body in [
          '',
          '<div id="thread_subject">topic</div>',
          '<p>someone said 评分成功</p>',
          '<script>errorhandle_rate("权限不足",{});succeedhandle_rate("","评分成功",{});</script>',
        ]) {
          expect(
            parsePostInteractionResult(
              body,
              PostInteractionKind.rating,
            ).isSuccess,
            isFalse,
          );
        }
        expect(
          parsePostInteractionResult(
            ratingSuccess,
            PostInteractionKind.rating,
            status: 302,
          ).kind,
          PostResultKind.unknown,
        );
      },
    );
  });
  test('captcha-bearing form cannot be submitted as a normal form', () {
    final raw = commentForm().replaceFirst(
      '</form>',
      '<input name="seccodeverify"></form>',
    );
    expect(parseInteractionPageError(raw)!.kind, PostResultKind.needCaptcha);
    expect(
      parsePostCommentForm(
        raw,
        tid: tid,
        pid: pid,
        pageUrl: interactionPageUrl(PostInteractionKind.comment, tid, pid),
      ),
      isNull,
    );
  });
  group('interaction repository', () {
    for (final kind in PostInteractionKind.values) {
      for (final status in [-1, 302, 307, 308]) {
        test(
          'uncertain AJAX $kind POST $status never switches transport or replays',
          () async {
            final a = Fake(
              onGet: (_) => ChhResponse(
                200,
                kind == PostInteractionKind.rating ? rateForm() : commentForm(),
              ),
              onPost: (_, _) => ChhResponse(
                status,
                status < 0 ? '' : '<div class="alert_error">remote_addr</div>',
              ),
            );
            final b = Fake(
              onGet: (_) => ChhResponse(
                200,
                kind == PostInteractionKind.rating ? rateForm() : commentForm(),
              ),
              onPost: (_, _) => const ChhResponse(200, ratingSuccess),
            );
            final repo = PostInteractionRepository(ChhClient(fetchers: [a, b]));
            final result = kind == PostInteractionKind.rating
                ? await repo.submitRating(
                    form: await repo.rateForm(tid: tid, pid: pid),
                    scores: {'score1': 1},
                  )
                : await repo.submitComment(
                    form: await repo.commentForm(tid: tid, pid: pid),
                    message: 'hello',
                  );
            expect(result.kind, PostResultKind.unknown);
            expect(a.ajaxPosts, 1);
            expect(b.posts, isEmpty);
          },
        );
      }
    }
    test(
      'rating form and submit use the ReSource AJAX request contract',
      () async {
        final f = Fake(
          onGet: (_) => ChhResponse(200, rateForm()),
          onPost: (_, _) => const ChhResponse(200, ratingSuccess),
        );
        final repo = PostInteractionRepository(ChhClient(fetchers: [f]));
        final form = await repo.rateForm(
          tid: tid,
          pid: pid,
          pageUrl: Uri.parse(
            'https://www.chiphell.com/forum.php?mod=misc&action=rate&tid=10&pid=20',
          ),
        );
        final result = await repo.submitRating(
          form: form,
          scores: {'score1': 1},
        );
        expect(result.isSuccess, isTrue);
        expect(f.ajaxPosts, 1);
        expect(f.posts, hasLength(1));
        for (var i = 0; i < f.gets.length; i++) {
          expect(f.gets[i].queryParameters['handlekey'], 'rate');
          expect(f.gets[i].queryParameters['ajaxtarget'], 'fwin_content_rate');
          expect(f.getHeaders[i]['X-Requested-With'], 'XMLHttpRequest');
        }
      },
    );
    test('AJAX cache never reuses ordinary HTML for the same URL', () async {
      final f = Fake(onGet: (_) => const ChhResponse(200, 'response'));
      final client = ChhClient(fetchers: [f]);
      final url = interactionPageUrl(PostInteractionKind.rating, tid, pid);
      await client.getHtml(url);
      await client.getAjaxHtml(url);
      await client.getAjaxHtml(url);
      expect(f.gets, hasLength(2));
      expect(f.getHeaders.first['X-Requested-With'], isNull);
      expect(f.getHeaders.last['X-Requested-With'], 'XMLHttpRequest');
    });
    test(
      'a genuine AJAX group denial is preserved and performs no POST',
      () async {
        final f = Fake(
          onGet: (_) => const ChhResponse(
            200,
            '<root><![CDATA[<div class="alert_error">抱歉，您所在的用户组无法进行此操作</div>]]></root>',
          ),
        );
        final repo = PostInteractionRepository(ChhClient(fetchers: [f]));
        await expectLater(
          repo.rateForm(tid: tid, pid: pid),
          throwsA(
            isA<PostInteractionException>().having(
              (e) => e.result.kind,
              'kind',
              PostResultKind.permissionDenied,
            ),
          ),
        );
        expect(f.posts, isEmpty);
      },
    );
    test(
      'comment fresh token, exact POST route and preserved hidden fields',
      () async {
        var count = 0;
        final f = Fake(
          onGet: (_) => ChhResponse(200, commentForm('token${++count}')),
        );
        final repo = PostInteractionRepository(
          ChhClient(fetchers: [f]),
          sessionIdentity: () => 'actor',
        );
        final form = await repo.commentForm(
          tid: tid,
          pid: pid,
          pageUrl: Uri.parse(
            'https://www.chiphell.com/forum.php?mod=misc&action=comment&tid=10&pid=20',
          ),
        );
        expect(
          (await repo.submitComment(form: form, message: 'hello')).isSuccess,
          isTrue,
        );
        expect(f.ajaxPosts, 1);
        for (var i = 0; i < f.gets.length; i++) {
          expect(f.getHeaders[i]['X-Requested-With'], 'XMLHttpRequest');
          expect(f.gets[i].queryParameters['handlekey'], 'comment');
          expect(
            f.gets[i].queryParameters['ajaxtarget'],
            'fwin_content_comment',
          );
          expect(f.gets[i].queryParameters['extra'], '');
        }
        expect(f.posts.single.fields['referer'], f.gets.last.toString());
        expect(f.posts.single.url.queryParameters['extra'], '');
        expect(f.posts.single.fields['formhash'], 'token2');
        expect(f.posts.single.fields['custom'], 'retained');
        expect(f.posts.single.url.queryParameters['mod'], 'post');
        expect(f.posts.single.url.queryParameters['action'], 'reply');
        expect(f.posts.single.url.queryParameters['comment'], 'yes');
      },
    );
    test(
      'score values/remaining rechecked against fresh form; hidden other type stays zero',
      () async {
        final f = Fake(
          onGet: (_) => ChhResponse(200, rateForm()),
          onPost: (_, _) => const ChhResponse(200, ratingSuccess),
        );
        final repo = PostInteractionRepository(ChhClient(fetchers: [f]));
        final form = await repo.rateForm(tid: tid, pid: pid);
        expect(
          (await repo.submitRating(
            form: form,
            scores: {'score1': 5},
          )).isSuccess,
          isFalse,
        );
        expect(f.posts, isEmpty);
        expect(
          (await repo.submitRating(
            form: form,
            scores: {'score1': -3},
            reason: '原样理由',
            notify: true,
          )).isSuccess,
          isTrue,
        );
        final fields = f.posts.single.fields;
        expect(fields['score1'], '-3');
        expect(fields['score8'], '0');
        expect(fields['sendreasonpm'], '1');
        expect(fields['reason'], '原样理由');
      },
    );
    test(
      'unknown keys, portal scores and empty scores rejected without POST',
      () async {
        final f = Fake(onGet: (_) => ChhResponse(200, rateForm()));
        final repo = PostInteractionRepository(ChhClient(fetchers: [f]));
        final form = await repo.rateForm(tid: tid, pid: pid);
        for (final scores in [
          {'score9': 1},
          {'score1': 1, 'score8': 1},
          <String, int>{},
        ]) {
          expect(
            (await repo.submitRating(form: form, scores: scores)).isSuccess,
            isFalse,
          );
        }
        expect(f.posts, isEmpty);
      },
    );
    test('account changes invalidate loaded form and pending GET', () async {
      String? actor = 'one';
      final f = Fake();
      final repo = PostInteractionRepository(
        ChhClient(fetchers: [f]),
        sessionIdentity: () => actor,
      );
      final form = await repo.commentForm(tid: tid, pid: pid);
      actor = 'two';
      expect(
        (await repo.submitComment(form: form, message: 'hello')).kind,
        PostResultKind.loginRequired,
      );
      expect(f.posts, isEmpty);
      final gate = Completer<ChhResponse>();
      final pending = PostInteractionRepository(
        ChhClient(fetchers: [Fake(onGet: (_) => gate.future)]),
        sessionIdentity: () => actor,
      ).commentForm(tid: tid, pid: pid);
      actor = 'three';
      gate.complete(ChhResponse(200, commentForm()));
      await expectLater(pending, throwsA(isA<PostInteractionException>()));
    });
    test('timeout never replays POST on another transport', () async {
      final a = Fake(onPost: (_, _) => ChhResponse.timeout), b = Fake();
      final repo = PostInteractionRepository(ChhClient(fetchers: [a, b]));
      final form = await repo.commentForm(tid: tid, pid: pid);
      expect(
        (await repo.submitComment(form: form, message: 'hello')).kind,
        PostResultKind.unknown,
      );
      expect(a.posts.length, 1);
      expect(b.posts, isEmpty);
    });
    test('certain WAF rejection can move to another transport', () async {
      final a = Fake(onPost: (_, _) => const ChhResponse(567, 'remote_addr')),
          b = Fake();
      final repo = PostInteractionRepository(ChhClient(fetchers: [a, b]));
      final form = await repo.commentForm(tid: tid, pid: pid);
      expect(
        (await repo.submitComment(form: form, message: 'hello')).isSuccess,
        isTrue,
      );
      expect(a.posts.length, 1);
      expect(b.posts.length, 1);
    });
    test('simultaneous submit is locked until POST completes', () async {
      final gate = Completer<ChhResponse>();
      final f = Fake(onPost: (_, _) => gate.future);
      final repo = PostInteractionRepository(ChhClient(fetchers: [f]));
      final form = await repo.commentForm(tid: tid, pid: pid);
      final first = repo.submitComment(form: form, message: 'hello');
      await Future<void>.delayed(Duration.zero);
      expect(
        (await repo.submitComment(form: form, message: 'duplicate')).isSuccess,
        isFalse,
      );
      gate.complete(const ChhResponse(200, commentSuccess));
      expect((await first).isSuccess, isTrue);
      expect(f.posts.length, 1);
    });
    test('server fresh refusal prevents any POST', () async {
      var count = 0;
      final f = Fake(
        onGet: (_) => ChhResponse(
          200,
          ++count == 1 ? rateForm() : '<div id="messagetext">权限不足</div>',
        ),
      );
      final repo = PostInteractionRepository(ChhClient(fetchers: [f]));
      final form = await repo.rateForm(tid: tid, pid: pid);
      expect(
        (await repo.submitRating(form: form, scores: {'score1': 1})).kind,
        PostResultKind.permissionDenied,
      );
      expect(f.posts, isEmpty);
    });
    test(
      'same UID revision changes invalidate both pending form reads',
      () async {
        for (final rating in [false, true]) {
          var revision = 0;
          final gate = Completer<ChhResponse>();
          final f = Fake(onGet: (_) => gate.future);
          final repo = PostInteractionRepository(
            ChhClient(fetchers: [f]),
            sessionIdentity: () => 'same-user',
            sessionRevision: () => revision,
          );
          final Future<Object> pending = rating
              ? repo.rateForm(tid: tid, pid: pid)
              : repo.commentForm(tid: tid, pid: pid);
          revision++;
          gate.complete(ChhResponse(200, rating ? rateForm() : commentForm()));
          await expectLater(pending, throwsA(isA<PostInteractionException>()));
          expect(f.posts, isEmpty);
        }
      },
    );
    test(
      'same UID re-login invalidates old form before refresh or POST',
      () async {
        var revision = 0;
        final f = Fake();
        final repo = PostInteractionRepository(
          ChhClient(fetchers: [f]),
          sessionIdentity: () => 'same-user',
          sessionRevision: () => revision,
        );
        final form = await repo.commentForm(tid: tid, pid: pid);
        expect(form.sessionRevision, 0);
        revision++;
        final r = await repo.submitComment(form: form, message: 'do not send');
        expect(r.kind, PostResultKind.loginRequired);
        expect(f.gets.length, 1);
        expect(f.posts, isEmpty);
      },
    );
    test(
      'same UID revision changes during fresh submit GET prevent POST',
      () async {
        var revision = 0;
        var reads = 0;
        final gate = Completer<ChhResponse>();
        final f = Fake(
          onGet: (_) =>
              ++reads == 1 ? ChhResponse(200, rateForm()) : gate.future,
        );
        final repo = PostInteractionRepository(
          ChhClient(fetchers: [f]),
          sessionIdentity: () => 'same-user',
          sessionRevision: () => revision,
        );
        final form = await repo.rateForm(tid: tid, pid: pid);
        final pending = repo.submitRating(form: form, scores: {'score1': 1});
        await Future<void>.delayed(Duration.zero);
        revision++;
        gate.complete(ChhResponse(200, rateForm()));
        expect((await pending).kind, PostResultKind.loginRequired);
        expect(f.posts, isEmpty);
      },
    );
    test(
      'revision change after POST cannot report success to a new session',
      () async {
        var revision = 0;
        final f = Fake(
          onPost: (_, _) {
            revision++;
            return const ChhResponse(200, commentSuccess);
          },
        );
        final repo = PostInteractionRepository(
          ChhClient(fetchers: [f]),
          sessionIdentity: () => 'same-user',
          sessionRevision: () => revision,
        );
        final form = await repo.commentForm(tid: tid, pid: pid);
        expect(
          (await repo.submitComment(form: form, message: 'message')).kind,
          PostResultKind.loginRequired,
        );
        expect(f.posts.length, 1);
      },
    );
    test(
      'hidden unparsed nonzero score never reaches POST; hidden zero is dropped',
      () async {
        for (final value in ['50', '0']) {
          final raw = rateForm().replaceFirst(
            '<table',
            '<input type="hidden" name="score99" value="$value"><table',
          );
          final f = Fake(
            onGet: (_) => ChhResponse(200, raw),
            onPost: (_, _) => const ChhResponse(200, ratingSuccess),
          );
          final repo = PostInteractionRepository(ChhClient(fetchers: [f]));
          final form = await repo.rateForm(tid: tid, pid: pid);
          final r = await repo.submitRating(form: form, scores: {'score1': 1});
          if (value == '50') {
            expect(r.isSuccess, isFalse);
            expect(f.posts, isEmpty);
          } else {
            expect(r.isSuccess, isTrue);
            expect(f.posts.single.fields.containsKey('score99'), isFalse);
          }
        }
      },
    );
    test(
      'quoted success code in a normal post is never an interaction success',
      () {
        for (final raw in [
          '<pre>succeedhandle_rate("", "评分成功", {});</pre>',
          '<div id="thread_subject">thread</div><script>succeedhandle_rate("", "评分成功", {});</script>',
          '<table><tr><td id="postmessage_20"><div class="alert_right">评分成功</div></td></tr></table>',
        ]) {
          expect(
            parsePostInteractionResult(raw, PostInteractionKind.rating).kind,
            PostResultKind.unknown,
          );
        }
      },
    );
  });
}
