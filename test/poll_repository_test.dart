import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:chh_app/data/poll_repository.dart';
import 'package:chh_app/models/poll.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:chh_app/parser/poll_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'poll_parser_test.dart' show fixture, thread;

class FakeClient extends ChhClient {
  FakeClient() : super(fetchers: []);
  final reads = <Uri>[];
  final refreshes = <bool>[];
  final posts = <List<MapEntry<String, String>>>[];
  final sources = <String>[];
  String response = '';
  Future<void> Function()? beforePost;
  Completer<void>? gate;
  @override
  Future<String> getHtml(
    Uri url, {
    bool refresh = false,
    bool fallback = true,
    bool Function()? shouldContinue,
  }) async {
    reads.add(url);
    refreshes.add(refresh);
    await gate?.future;
    return sources.removeAt(0);
  }

  @override
  Future<ChhResponse> postFormFields(
    Uri url,
    List<MapEntry<String, String>> form, {
    bool retryTransportFailures = true,
  }) async {
    expect(retryTransportFailures, isFalse);
    posts.add(form);
    await beforePost?.call();
    return ChhResponse(200, response);
  }
}

String available() => thread(fixture(2918339));
String voted() => available()
    .replaceAll(RegExp(r'<input[^>]+name="pollanswers\[\]"[^>]*>'), '')
    .replaceFirst('</tbody>', '<tr><td>您已经投过票，谢谢您的参与</td></tr></tbody>');
ThreadPoll poll() => parseThreadPoll(available(), tid: 2918339)!;
void main() {
  test(
    'fresh hash, POST fields, uncached confirmation and persisted choices',
    () async {
      final dir = await Directory.systemTemp.createTemp('poll-test');
      addTearDown(() => dir.delete(recursive: true));
      final client = FakeClient()..sources.addAll([available(), voted()]);
      var uid = 1;
      final repo = PollRepository(client, uid: () => uid);
      final file = File('${dir.path}/poll.json');
      await repo.attach(file);
      final result = await repo.vote(poll(), {'22596'});
      expect(result.success, isTrue);
      expect(result.poll!.options.first.mine, isTrue);
      expect(Map.fromEntries(client.posts.single), {
        'formhash': 'REDACTED',
        'pollanswers[]': '22596',
        'pollsubmit': 'true',
      });
      expect(client.refreshes, [true, true]);
      expect(
        client.reads.every((u) => u.path == '/thread-2918339-1-1.html'),
        isTrue,
      );
      final restored = PollRepository(FakeClient(), uid: () => uid);
      await restored.attach(file);
      expect(
        (await restored.withMyChoices(result.poll!)).options.first.mine,
        isTrue,
      );
      uid = 2;
      expect(
        (await restored.withMyChoices(
          result.poll!,
        )).options.every((o) => !o.mine),
        isTrue,
      );
    },
  );
  test('synthetic multi choice sends repeated pollanswers[] fields', () async {
    final source = available()
        .replaceFirst('单选投票', '多选投票 最多可选 2 项')
        .replaceAll('type="radio"', 'type="checkbox"');
    final after = source.replaceFirst(
      '</tbody>',
      '<tr><td>您已经投过票，谢谢您的参与</td></tr></tbody>',
    );
    final client = FakeClient()..sources.addAll([source, after]);
    final result = await PollRepository(
      client,
      uid: () => 1,
    ).vote(parseThreadPoll(source, tid: 2918339)!, {'22596', '22597'});
    expect(result.success, isTrue);
    expect(
      client.posts.single
          .where((e) => e.key == 'pollanswers[]')
          .map((e) => e.value),
      ['22596', '22597'],
    );
    expect(result.poll!.options.where((o) => o.mine).length, 2);
  });
  test('failure preserves server reason and does not record choices', () async {
    final client = FakeClient()
      ..sources.addAll([available(), available()])
      ..response = '<div id="messagetext"><p>没有权限</p></div>';
    final repo = PollRepository(client, uid: () => 1);
    final result = await repo.vote(poll(), {'22596'});
    expect(result.success, isFalse);
    expect(result.message, contains('没有权限'));
    expect(
      (await repo.withMyChoices(poll())).options.every((o) => !o.mine),
      isTrue,
    );
  });
  test(
    'rejects invalid choices, duplicate submit, guest and session change',
    () async {
      final client = FakeClient()
        ..sources.add(available())
        ..gate = Completer();
      var uid = 1;
      final repo = PollRepository(client, uid: () => uid);
      final first = repo.vote(poll(), {'22596'});
      expect((await repo.vote(poll(), {'22596'})).success, isFalse);
      uid = 2;
      client.gate!.complete();
      expect((await first).success, isFalse);
      expect(client.posts, isEmpty);
      final invalid = FakeClient()..sources.add(available());
      expect(
        (await PollRepository(
          invalid,
          uid: () => 1,
        ).vote(poll(), {'fake'})).success,
        isFalse,
      );
      expect(invalid.posts, isEmpty);
      expect(
        (await PollRepository(FakeClient()).vote(poll(), {'22596'})).message,
        '请先登录',
      );
    },
  );
  for (final response in [
    '',
    '<div id="messagetext"><p>没有权限</p></div>',
    '<div id="messagetext"><p>需要完成验证码</p></div>',
  ]) {
    test(
      'other voters changing counts cannot confirm our vote: $response',
      () async {
        final client = FakeClient()
          ..response = response
          ..sources.addAll([
            available(),
            available().replaceFirst('(269)', '(270)'),
          ]);
        final repo = PollRepository(client, uid: () => 1);
        final result = await repo.vote(poll(), {'22596'});
        expect(result.success, isFalse);
        expect(result.poll!.canVote, isTrue);
        expect(
          (await repo.withMyChoices(poll())).options.every((o) => !o.mine),
          isTrue,
        );
        expect(client.posts, hasLength(1));
        if (response.isNotEmpty) {
          expect(
            result.message,
            contains(response.contains('验证码') ? '验证' : '没有权限'),
          );
        }
      },
    );
  }
  test(
    'explicit rejection cannot claim choices submitted from another device',
    () async {
      final client = FakeClient()
        ..response = '<div id="messagetext"><p>没有权限</p></div>'
        ..sources.addAll([available(), voted()]);
      final repo = PollRepository(client, uid: () => 1);
      final result = await repo.vote(poll(), {'22596'});
      expect(result.success, isFalse);
      expect(result.poll!.alreadyVoted, isTrue);
      expect(result.message, contains('没有权限'));
      expect(
        (await repo.withMyChoices(poll())).options.every((o) => !o.mine),
        isTrue,
      );
    },
  );
  test('corrupt storage entry does not discard later valid choices', () async {
    final dir = await Directory.systemTemp.createTemp('poll-test');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/poll.json');
    await file.writeAsString(
      jsonEncode({
        'version': 1,
        'choices': {
          'bad': {'id': 2},
          '1:2918339': {'22596': poll().options.first.text},
        },
      }),
    );
    final repo = PollRepository(FakeClient(), uid: () => 1);
    await repo.attach(file);
    expect((await repo.withMyChoices(poll())).options.first.mine, isTrue);
  });
  test(
    'participants GET encodes option and page; propagates permission and errors',
    () async {
      final source = fixture(2864777);
      final p = parseThreadPoll(thread(source), tid: 2864777)!;
      final client = FakeClient()
        ..sources.addAll([
          '<select class="ps"><option value="a">甲</option></select><ul class="voterl"></ul>',
          '<div id="messagetext"><p>没有权限</p></div>',
        ]);
      final repo = PollRepository(client, uid: () => 1);
      expect(
        (await repo.participants(p, optionId: 'a', page: 2)).voters,
        isEmpty,
      );
      expect(client.reads.single.queryParameters['polloptionid'], 'a');
      expect(client.reads.single.queryParameters['page'], '2');
      expect(client.posts, isEmpty);
      await expectLater(repo.participants(p), throwsA(anything));
      await expectLater(repo.participants(p), throwsA(anything));
    },
  );
  test('server permission message on refreshed page is shown', () async {
    final client = FakeClient()
      ..sources.addAll([
        available(),
        '<div id="messagetext"><p>没有权限</p></div>',
      ]);
    final result = await PollRepository(
      client,
      uid: () => 1,
    ).vote(poll(), {'22596'});
    expect(result.success, isFalse);
    expect(result.message, contains('没有权限'));
  });
}
