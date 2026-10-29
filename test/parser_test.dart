/// 解析器回归测试:直接对合成的 Discuz 结构样本断言
/// 样本更新方式见 test_data/README.md
library;

import 'dart:io';

import 'package:chh_app/models/models.dart';
import 'package:chh_app/parser/forum_index_parser.dart';
import 'package:chh_app/parser/guide_parser.dart';
import 'package:chh_app/parser/search_result_parser.dart';
import 'package:chh_app/parser/thread_list_parser.dart';
import 'package:chh_app/parser/thread_parser.dart';
import 'package:flutter_test/flutter_test.dart';

String sample(String name) => File('test_data/$name').readAsStringSync();

void main() {
  group('论坛首页解析 forum_index_synthetic.html', () {
    test('解析出分组与版块', () {
      final cats = parseForumIndex(sample('forum_index_synthetic.html'));
      expect(cats.length, greaterThanOrEqualTo(4));

      final names = cats.map((c) => c.name).toList();
      expect(names, contains('管理分区'));

      final station = cats.firstWhere((c) => c.name == '管理分区');
      final forums = station.forums.map((f) => f.name).toList();
      expect(forums, contains('问题反馈'));
    });

    test('版块统计数解析(含"4万"简写)', () {
      final cats = parseForumIndex(sample('forum_index_synthetic.html'));
      final all = cats.expand((c) => c.forums);
      final jb = all.firstWhere((f) => f.fid == 110);
      expect(jb.name, '问题反馈');
      expect(jb.threadCount, 107);
      expect(jb.lastPostTimeRaw, isNotNull);
      // 帖数带"万"的至少能解出一个值
      expect(all.any((f) => (f.postCount ?? 0) > 1000), isTrue);
    });
  });

  group('版块页解析 thread_list_synthetic.html', () {
    test('解析 15 条常规帖 + 6 条置顶', () {
      final page = parseThreadList(sample('thread_list_synthetic.html'));
      final normal = page.threads.where((t) => !t.sticky).toList();
      final sticky = page.threads.where((t) => t.sticky).toList();
      expect(normal.length, 15);
      expect(sticky.length, 6);
      expect(page.page.current, 1);
    });

    test('单条帖子字段完整(tid 900101)', () {
      final page = parseThreadList(sample('thread_list_synthetic.html'));
      final t = page.threads.firstWhere((t) => t.tid == 900101);
      expect(t.title, contains('mini sea view'));
      expect(t.author, '示例作者甲');
      expect(t.typeName, 'ITX');
      expect(t.replies, 2);
      expect(t.views, 1434);
      expect(t.hasImages, isTrue);
      expect(t.createdAt, DateTime(2026, 1, 2, 3, 4));
      expect(t.lastPostUser, '示例作者乙');
      expect(t.sticky, isFalse);
    });
  });

  group('帖子详情解析 thread_synthetic.html', () {
    test('楼层与首楼字段', () {
      final d = parseThread(sample('thread_synthetic.html'), tid: 900001);
      expect(d.title, isNotEmpty);
      expect(d.posts.length, greaterThanOrEqualTo(8));

      final first = d.posts.first;
      expect(first.author, '示例作者甲');
      expect(first.authorUid, '1001');
      expect(first.floor, 1);
      expect(first.time, DateTime(2026, 1, 2, 3, 4));
      expect(first.avatarUrl, 'https://example.invalid/avatar-1001.png');
    });

    test('正文图片从 zoomfile 属性提取(static.chiphell.com)', () {
      final d = parseThread(sample('thread_synthetic.html'), tid: 900001);
      final images = d.posts
          .expand((p) => p.content)
          .whereType<ImageBlock>()
          .map((b) => b.url)
          .toList();
      expect(images.length, 2);
      expect(
        images.every((u) => u.startsWith('https://static.chiphell.com/')),
        isTrue,
      );
    });

    test('正文文本块非空', () {
      final d = parseThread(sample('thread_synthetic.html'), tid: 900001);
      final texts = d.posts.expand((p) => p.content).whereType<TextBlock>();
      expect(texts.any((b) => b.text.length > 10), isTrue);
    });
  });

  group('搜索结果解析 search_synthetic.html', () {
    test('解析 48 条结果与首条字段', () {
      final p = parseSearchResult(sample('search_synthetic.html'));
      expect(p.rows.length, 48);

      final r = p.rows.first;
      expect(r.tid, 900201);
      expect(r.title, contains('4090'));
      expect(r.title, contains('48G'));
      expect(r.replies, 2);
      expect(r.views, 1076);
      expect(r.author, '示例搜索作者1');
      expect(r.forumName, '示例电脑区');
      expect(r.forumFid, 146);
      expect(r.snippet, isNotNull);
    });

    test('翻页信息', () {
      final p = parseSearchResult(sample('search_synthetic.html'));
      expect(p.page.current, 1);
      expect(p.page.hasNext, isTrue);
      expect(p.nextUrl, contains('searchid='));
      expect(p.nextUrl, startsWith('https://www.chiphell.com/'));
    });
  });

  group('guide 解析 guide_synthetic.html', () {
    test('解析 50 条最新回复', () {
      final p = parseGuide(sample('guide_synthetic.html'));
      expect(p.threads.length, 50);

      final t = p.threads.first;
      expect(t.tid, 900301);
      expect(t.title, contains('装机赛'));
      expect(t.forumName, contains('示例装机区'));
      expect(t.forumFid, 290);
      expect(t.author, '示例动态作者1');
      expect(t.replies, 3);
      expect(t.views, 393);
    });
  });

  _postExtrasTests();
}

/// 楼层附属内容的解析
///
/// 依据合成样本 thread_synthetic.html:
///   编辑说明 <i class="pstatus">本帖最后由 … 编辑</i>
///   评分     <dl id="ratelog_{pid}" class="rate"> → th 汇总 + tbody.ratl_l 明细
void _postExtrasTests() {
  group('楼层附属内容', () {
    test('编辑说明从正文摘出,不再混在正文里', () {
      final d = parseThread(sample('thread_synthetic.html'), tid: 900001);
      final first = d.posts.first;

      expect(first.notes, isNotEmpty);
      expect(first.notes.first.kind, PostNoteKind.edited);
      expect(first.notes.first.text, contains('本帖最后由'));

      final body = first.content
          .whereType<TextBlock>()
          .map((b) => b.text)
          .join(' ');
      expect(body, isNot(contains('本帖最后由')));
    });

    test('评分汇总与明细', () {
      final d = parseThread(sample('thread_synthetic.html'), tid: 900001);
      final rating = d.posts.firstWhere((p) => p.rating != null).rating!;

      expect(rating.summary.join(' '), contains('参与人数'));
      expect(rating.summary.join(' '), contains('邪恶指数'));
      // 操作列不算汇总
      expect(rating.summary.join(' '), isNot(contains('收起')));

      expect(rating.entries.length, 2);
      expect(rating.entries.first.user, '示例评分者甲');
      expect(rating.entries.first.score, '+ 100');
      expect(rating.entries.first.reason, '示例评分理由');
      expect(rating.entries.first.uid, '2001');
    });

    test('没有点评时为空,不造假数据', () {
      final d = parseThread(sample('thread_synthetic.html'), tid: 900001);
      expect(d.posts.first.comments, isEmpty);
    });
  });

  _smileyTests();
}

/// 论坛表情
///
/// 站点形态:<img src="static/image/smiley/diy/fd.gif" smilieid="390">
/// 表情穿插在文字中间,不能当独立图片块,否则一句话会被切碎。
void _smileyTests() {
  group('表情', () {
    test('合成样本里的表情被保留为内联片段', () {
      final d = parseThread(sample('thread_synthetic.html'), tid: 900001);
      final blocks = d.posts.first.content.whereType<TextBlock>();
      final withSmiley = blocks.where((b) => b.hasInline);

      expect(withSmiley, isNotEmpty);
      expect(
        withSmiley.first.nodes.whereType<InlineSmiley>().first.url,
        contains('static/image/smiley/'),
      );
    });

    test('表情不会被当成正文图片', () {
      final d = parseThread(sample('thread_synthetic.html'), tid: 900001);
      final images = d.posts.first.content.whereType<ImageBlock>();
      expect(images.where((i) => i.url.contains('smiley')), isEmpty);
    });

    test('纯文本形态不含表情,便于摘要与搜索', () {
      final d = parseThread(sample('thread_synthetic.html'), tid: 900001);
      final b = d.posts.first.content.whereType<TextBlock>().firstWhere(
        (b) => b.hasInline,
      );
      expect(b.text, isNot(contains('smiley')));
      expect(b.text.trim(), isNotEmpty);
    });

    test('没有表情的段落不产出内联序列', () {
      final d = parseThread(sample('thread_synthetic.html'), tid: 900001);
      final plain = d.posts.first.content.whereType<TextBlock>().where(
        (b) => !b.hasInline,
      );
      expect(plain, isNotEmpty);
      expect(plain.first.nodes, isEmpty);
    });
  });
}
