import 'dart:io';
import 'dart:convert';
import 'package:html/parser.dart' as html;
import 'package:chh_app/parser/poll_parser.dart';
import 'package:chh_app/parser/thread_parser.dart';
import 'package:chh_app/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

String fixture(int tid) =>
    File('test/fixtures/polls/$tid.html').readAsStringSync();
String thread(String poll, {int floor = 1}) =>
    '<div id="postlist"><table id="pid100"><tr><td><div class="authi"><strong><a href="space-uid-1.html">作者</a></strong></div><a id="postnum100">$floor#</a><div class="pcbs"><table><tr><td id="postmessage_100">正文<img src="https://www.chiphell.com/image.jpg"></td></tr></table>$poll</div></td></tr></table></div>';
void main() {
  final cases = [
    (2918339, false, 1, 331, 3, false, false, false, true, false),
    (2864777, true, 2, 478, 5, false, false, true, true, true),
    (2849977, false, 1, 863, 12, true, false, true, true, false),
    (2839624, true, 5, 596, 42, false, true, false, false, false),
    (2584870, true, 5, 244, 15, true, true, false, true, true),
    (2786283, false, 1, 220, 2, false, false, false, false, false),
  ];
  for (final c in cases) {
    test('poll fixture ${c.$1} preserves observed data', () {
      final source = fixture(c.$1);
      final poll = parsePollElement(
        html.parse(source).querySelector('form#poll'),
        tid: c.$1,
      )!;
      expect(poll.multiple, c.$2);
      expect(poll.maxChoices, c.$3);
      expect(poll.participantCount, c.$4);
      expect(poll.options.length, c.$5);
      expect(poll.ended, c.$6);
      expect(poll.closed, c.$7);
      expect(poll.alreadyVoted, c.$8);
      expect(poll.hasResults, c.$9);
      expect(poll.participantsUrl != null, c.$10);
      expect(poll.action!.queryParameters['tid'], '${c.$1}');
      final expected =
          jsonDecode(
                File('test/fixtures/polls/expected.json').readAsStringSync(),
              )['${c.$1}']
              as List;
      expect(poll.options.length, expected.length);
      for (var i = 0; i < expected.length; i++) {
        expect(
          poll.options[i].text,
          (expected[i]['text'] as String)
              .replaceAll(RegExp(r'[\s ]+'), ' ')
              .trim(),
        );
        expect(poll.options[i].id, expected[i]['id']);
        expect(poll.options[i].votes, expected[i]['votes']);
        expect(poll.options[i].percentage, expected[i]['percentage']);
      }
      final doc = html.parse(source);
      final labels = doc.querySelectorAll('.pvt label');
      for (var i = 0; i < labels.length; i++) {
        final o = poll.options[i];
        expect(
          o.text,
          labels[i].text
              .replaceAll(RegExp(r'[\s ]+'), ' ')
              .trim()
              .replaceFirst(RegExp(r'^\d+\.\s*'), ''),
        );
        expect(
          o.id,
          labels[i].parent!.parent!
              .querySelector('input[name="pollanswers[]"]')
              ?.attributes['value'],
        );
        if (!c.$9) {
          expect(o.votes, isNull);
          expect(o.percentage, isNull);
        } else {
          expect(o.votes, isNotNull);
          expect(o.percentage, isNotNull);
        }
        if (c.$6 || c.$8) expect(o.id, isNull);
      }
      if (c.$1 == 2918339) {
        expect(poll.options.first.id, '22596');
        expect(poll.options.first.votes, 269);
        expect(poll.options.first.percentage, 81.27);
      }
      if (c.$1 == 2864777) expect(poll.deadline, '距结束还有: 1 天23 小时30 分钟');
      if (c.$1 == 2786283) expect(poll.resultsAfterVote, isTrue);
    });
  }
  test('body and attachment are unchanged and only opening floor has poll', () {
    final raw = thread(fixture(2918339));
    final result = parseThread(raw, tid: 2918339);
    expect(result.poll, isNotNull);
    final baseline = parseThread(thread(''), tid: 2918339);
    expect(
      result.posts.first.content.whereType<TextBlock>().map((b) => b.text),
      baseline.posts.first.content.whereType<TextBlock>().map((b) => b.text),
    );
    expect(result.posts.first.content.whereType<TextBlock>().single.text, '正文');
    expect(
      result.posts.first.content.whereType<ImageBlock>().single.url,
      'https://www.chiphell.com/image.jpg',
    );
    expect(
      parseThread(thread(fixture(2918339), floor: 2), tid: 2918339).poll,
      isNull,
    );
    expect(parseThread(raw, tid: 2918339, fallbackPage: 2).poll, isNull);
    expect(
      parseThreadPoll(
        thread(
          '<table><tr><td id="postmessage_999">${fixture(2918339)}</td></tr></table>',
        ),
        tid: 2918339,
      ),
      isNull,
    );
  });
  test('synthetic voters preserve option IDs, uid, avatar and pagination', () {
    final page = parsePollVoters(
      '<select class="ps"><option value="a">甲</option><option selected value="b">乙</option></select><ul class="voterl"><li><img src="/avatar.jpg"><p><a href="space-uid-123.html">样例会员</a></p></li></ul><div class="pg"><strong>2</strong><a class="nxt">下一页</a></div>',
    );
    expect(page.options.map((o) => o.id), ['a', 'b']);
    expect(page.selectedOptionId, 'b');
    expect(page.voters.single.uid, 123);
    expect(page.voters.single.name, '样例会员');
    expect(page.voters.single.avatarUrl, endsWith('/avatar.jpg'));
    expect(page.page.current, 2);
    expect(page.page.hasNext, isTrue);
    expect(parsePollVoters('<select class="ps"></select>').voters, isEmpty);
    expect(
      () => parsePollVoters('<div id="messagetext"><p>没有权限</p></div>'),
      throwsA(anything),
    );
  });
}
