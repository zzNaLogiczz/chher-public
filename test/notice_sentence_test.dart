import 'package:chh_app/parser/notice_parser.dart';
import 'package:flutter_test/flutter_test.dart';

const _actor = '<a href="space-uid-17.html">摆烂狗</a>';
const _title = '【公益项目】属于坛友自己的移动端APP';
const _link = '<a href="thread-25-1-1.html">$_title</a>';
const _view =
    '<a class="lit" href="forum.php?mod=redirect&amp;goto=findpost&amp;ptid=25&amp;pid=33">查看</a>';

String _notice(String action) =>
    '<dl id="notice_12"><dd class="ntc_body">$_actor $action $_view</dd></dl>';

void main() {
  group('评分提醒句子', () {
    for (final score in ['<span class="xi1">邪恶指数 +5</span>', '邪恶指数 +5']) {
      for (final reason in ['', '就是NB']) {
        test('清理被动句并保留真实分值与理由: $score / $reason', () {
          final n = parseNotices(
            _notice('您在主题 $_link 的帖子被 评分 $score &nbsp; $reason'),
            filterCategory: 'rate',
          ).items.single;
          expect(
            n.action,
            '评分了您的帖子　邪恶指数 +5${reason.isEmpty ? '' : '　$reason'}',
          );
          expect(n.actor, '摆烂狗');
          expect(n.title, _title);
          expect(n.score, '邪恶指数 +5');
          expect(n.summary, contains(_title));
          expect(n.summary, contains('的帖子被'));
          expect(n.targetUrl, contains('pid=33'));
          expect(n.tid, 25);
          expect(n.pid, 33);
          expect(n.unread, isFalse);
        });
      }
    }

    test('理由与评分共用强调标签时不把理由作为分值', () {
      final n = parseNotices(
        _notice('您在主题$_link的帖子被评分 <span class="xi1">邪恶指数 +5 就是NB</span>'),
        filterCategory: 'rate',
      ).items.single;
      expect(n.score, '邪恶指数 +5');
      expect(n.action, '评分了您的帖子　邪恶指数 +5　就是NB');
    });

    test('没有分值或理由就不补造', () {
      final n = parseNotices(
        _notice('您在主题$_link的帖子被评分'),
        filterCategory: 'rate',
      ).items.single;
      expect(n.action, '评分了您的帖子');
      expect(n.score, isNull);
    });

    test('负分和理由里的同名文本、主题语法保留', () {
      final n = parseNotices(
        _notice(
          '给您的回复 $_link 评分 <b class="xi1">激情 - 2</b> '
          '摆烂狗说：在主题 的帖子中写得不清楚',
        ),
        filterCategory: 'rate',
      ).items.single;
      expect(n.score, '激情 - 2');
      expect(n.action, '评分了您的帖子　激情 - 2　摆烂狗说：在主题 的帖子中写得不清楚');
    });
  });

  group('其他提醒去标题后的句子', () {
    for (final sample in [
      (type: 'pcomment', raw: '点评了您在主题 $_link 的帖子', want: '点评了您的帖子'),
      (type: 'pcomment', raw: '您在主题$_link的帖子被 点评', want: '点评了您的帖子'),
      (type: 'post', raw: '回复了您在主题 《$_link》 的帖子', want: '回复了您的帖子'),
      (type: 'post', raw: '回复了您的帖子　$_link　 &nbsp;', want: '回复了您的帖子'),
      (type: 'at', raw: '在主题 「$_link」 中提到了您', want: '在主题中提到了您'),
      (type: 'at', raw: '在主题 $_link 的回复 中提到了您', want: '在回复中提到了您'),
      (type: 'at', raw: '在主题 【$_link】 的帖子中提到了您', want: '在帖子中提到了您'),
    ]) {
      test('${sample.type}: ${sample.raw}', () {
        final n = parseNotices(
          _notice(sample.raw),
          filterCategory: sample.type,
        ).items.single;
        expect(n.action, sample.want);
        expect(n.action, isNot(contains(RegExp(r'\s{2,}'))));
        expect(n.actor, '摆烂狗');
        expect(n.title, _title);
        expect(n.pid, 33);
        expect(n.score, isNull);
      });
    }
  });
}
