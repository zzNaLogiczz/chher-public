import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/parser/notice_parser.dart';
import 'package:chh_app/parser/pm_parser.dart';
import 'package:chh_app/ui/plain_rows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _actor = '<a href="home.php?mod=space&amp;uid=17">合成坛友</a>';
const _title = '【公益项目】属于坛友自己的移动端APP';
const _view =
    '<a class="lit" href="forum.php?mod=redirect&amp;goto=findpost&amp;ptid=25&amp;pid=33">查看</a>';

String _notice(String body, {String type = 'post'}) =>
    '''
<dl id="notice_12"><dt><span class="xg1">2026-11-15 17:40</span>
<a href="home.php?mod=spacecp&amp;ac=common&amp;op=ignore&amp;type=$type">屏蔽</a></dt>
<dd class="ntc_body">$body</dd></dl>''';

String _conversation(String body, String time) =>
    '''
<div id="deletepmform"><dl id="pmlist_9"><dd class="pm_c">
<a href="home.php?mod=space&amp;do=pm&amp;subop=view&amp;touid=17">查看</a>
$body $time
</dd></dl></div>''';

void main() {
  group('B actual notice link roles', () {
    for (final href in [
      'thread-25-1-1.html',
      'forum.php?mod=viewthread&amp;tid=25',
      'forum.php?mod=redirect&amp;goto=findpost&amp;ptid=25&amp;pid=33',
      'forum.php?mod=redirect&amp;ptid=25',
    ]) {
      test('title comes from thread link and target retains pid: $href', () {
        final n = parseNotices(
          _notice('$_actor 回复了您的帖子 <a href="$href">$_title</a> $_view'),
        ).items.single;
        expect(n.title, _title);
        expect(n.action, '回复了您的帖子');
        expect(n.actor, '合成坛友');
        expect(n.pid, 33);
        expect(n.tid, 25);
        expect(n.targetUrl, contains('pid=33'));
        expect(n.summary, contains(_title));
      });
    }

    test('pid target wins even when the title has class lit', () {
      final n = parseNotices(
        _notice(
          '$_actor 回复了您的帖子 <a class="lit" href="thread-25-1-1.html">$_title</a> $_view',
        ),
      ).items.single;
      expect(n.title, _title);
      expect(n.pid, 33);
    });

    test('view-only notice has no title, incomplete pid is not fabricated', () {
      final n = parseNotices(_notice('$_actor 回复了您的帖子 $_view')).items.single;
      expect(n.title, isNull);
      expect(n.action, '回复了您的帖子');
      final missing = parseNotices(
        _notice(
          '$_actor 回复了您 <a class="lit" href="forum.php?mod=redirect&amp;goto=findpost&amp;ptid=25&amp;pid=">查看</a>',
        ),
      ).items.single;
      expect(missing.title, isNull);
      expect(missing.pid, isNull);
      expect(missing.targetUrl, isNull);
    });

    for (final style in AppearanceStyle.values) {
      for (final brightness in Brightness.values) {
        testWidgets('rating action and title render once $style $brightness', (
          tester,
        ) async {
          final n = parseNotices(
            _notice(
              '$_actor 您在主题 <a href="thread-25-1-1.html"><span class="xi1">$_title</span></a> '
              '的帖子被 评分 <span class="xi1">邪恶指数 +5</span> 就是NB $_view',
              type: 'rate',
            ),
          ).items.single;
          expect(n.action, '评分了您的帖子　邪恶指数 +5　就是NB');
          expect(n.score, '邪恶指数 +5');
          await tester.pumpWidget(
            MaterialApp(
              theme: buildAppTheme(brightness, style),
              home: Scaffold(
                body: NoticeRow(
                  avatar: const SizedBox(),
                  name: n.actor!,
                  time: '17:40',
                  text: n.action!,
                  title: n.title,
                  scoreText: n.score,
                ),
              ),
            ),
          );
          final finder = find.byKey(const ValueKey('notice-sentence'));
          final sentence = tester.widget<Text>(finder).textSpan! as TextSpan;
          expect(sentence.toPlainText(), '合成坛友 评分了您的帖子 就是NB');
          final score = tester.widget<Text>(
            find.byKey(const ValueKey('notice-score')),
          );
          expect(score.data, '邪恶指数 +5');
          expect(
            score.style!.color,
            AppTokens.of(tester.element(finder)).accent,
          );
          expect(find.text('《$_title》'), findsOneWidget);
          expect(find.text('查看'), findsNothing);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('missing title omits quote block', (tester) async {
      final n = parseNotices(_notice('$_actor 回复了您的帖子 $_view')).items.single;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: Scaffold(
            body: NoticeRow(
              avatar: const SizedBox(),
              name: n.actor!,
              time: '',
              text: n.action!,
              title: n.title,
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('notice-quote')), findsNothing);
      expect(find.byKey(const ValueKey('notice-title')), findsNothing);
      expect(find.text('查看'), findsNothing);
    });
  });

  group('C source PM preview variants', () {
    for (final prefix in [
      '$_actor 对 您 说 :',
      '$_actor 对您说：',
      '$_actor 对 您说 : ',
    ]) {
      test('incoming spaced prefix: $prefix', () {
        final c = parsePmList(
          _conversation(
            '$prefix可以，等迭代版。',
            '<span class="xg1">2026-11-13 14:04</span>',
          ),
        ).items.single;
        expect(c.preview, '可以，等迭代版。');
        expect(c.isOutgoing, isFalse);
        expect(c.peer, '合成坛友');
        expect(c.timeRaw, '2026-11-13 14:04');
      });
    }
    for (final time in ['2026-11-13 14:04', '2026-11-3 19:39']) {
      test('outgoing preview strips bare trailing date: $time', () {
        final c = parsePmList(
          _conversation('您 对 $_actor 说 :好的 我记录一下', time),
        ).items.single;
        expect(c.preview, '好的 我记录一下');
        expect(c.isOutgoing, isTrue);
        expect(c.timeRaw, time);
      });
    }
    test('date inside message body and repeated peer name stay intact', () {
      final c = parsePmList(
        _conversation(
          '$_actor 对 您 说 :合成坛友说 2026-11-3 19:39 可以见面',
          '<em>2026-11-13 14:04</em>',
        ),
      ).items.single;
      expect(c.preview, '合成坛友说 2026-11-3 19:39 可以见面');
    });
  });
}
