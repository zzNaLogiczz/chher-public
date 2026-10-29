/// URL 构造单测
///
/// 回归用:帖子详情的伪静态把页码写到了第 3 段(那是 authorid),
/// 导致任何页码都取回第 1 页,表现为能一直翻页但内容不变。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:chh_app/core/chh_urls.dart';
import 'package:chh_app/data/forum_repository.dart';
import 'package:chh_app/models/thread_sort.dart';
import 'package:chh_app/network/chh_client.dart';

class _RecordingClient extends ChhClient {
  _RecordingClient(this.html) : super(fetchers: []);

  final String html;
  Uri? requestedUrl;
  bool? requestedRefresh;

  @override
  Future<String> getHtml(
    Uri url, {
    bool refresh = false,
    bool fallback = true,
  }) async {
    requestedUrl = url;
    requestedRefresh = refresh;
    return html;
  }
}

void main() {
  group('帖子详情地址', () {
    test('页码在第 2 段', () {
      expect(
        ChhUrls.thread(900001, page: 3).toString(),
        'https://www.chiphell.com/thread-900001-3-1.html',
      );
    });

    test('默认第 1 页', () {
      expect(
        ChhUrls.thread(900001).toString(),
        'https://www.chiphell.com/thread-900001-1-1.html',
      );
    });

    test('只看作者走查询串形态,页码单独带', () {
      final u = ChhUrls.threadByAuthor(900001, '12345', page: 2);
      expect(u.queryParameters['tid'], '900001');
      expect(u.queryParameters['authorid'], '12345');
      expect(u.queryParameters['page'], '2');
    });
  });

  group('版块列表地址', () {
    test('分类筛选要同时带 filter 与 typeid', () {
      final u = ChhUrls.threadListFiltered(290, page: 2, typeid: 1010);
      expect(u.queryParameters['filter'], 'typeid');
      expect(u.queryParameters['typeid'], '1010');
      expect(u.queryParameters['page'], '2');
    });

    test('排序单独生效:带站点配对的 filter 与 orderby', () {
      final u = ChhUrls.threadListFiltered(
        290,
        orderby: 'replies',
        filter: 'reply',
      );
      expect(u.queryParameters['filter'], 'reply');
      expect(u.queryParameters['orderby'], 'replies');
    });

    for (final orderby in ['dateline', 'replies', 'views']) {
      test('分类与排序可以共存:$orderby', () {
        final u = ChhUrls.threadListFiltered(
          290,
          page: 2,
          typeid: 1010,
          filter: 'reply',
          orderby: orderby,
        );
        expect(u.queryParameters['filter'], 'typeid');
        expect(u.queryParameters['typeid'], '1010');
        expect(u.queryParameters['orderby'], orderby);
        expect(u.queryParameters['page'], '2');
      });
    }

    test('裸 orderby 仍保留参数与页码', () {
      final u = ChhUrls.threadListFiltered(290, page: 2, orderby: 'views');
      expect(u.queryParameters['orderby'], 'views');
      expect(u.queryParameters['page'], '2');
      expect(u.queryParameters.containsKey('filter'), isFalse);
    });

    test('默认排序不带 filter 与 orderby', () {
      final u = ChhUrls.threadListFiltered(290);
      expect(u.queryParameters.containsKey('filter'), isFalse);
      expect(u.queryParameters.containsKey('orderby'), isFalse);
    });

    test('typeid 为 0 视为不筛选', () {
      final u = ChhUrls.threadListFiltered(290, typeid: 0);
      expect(u.queryParameters.containsKey('typeid'), isFalse);
    });
  });

  group('ThreadSort 参数映射', () {
    test('四种排序的站点参数与实测一致', () {
      expect(ThreadSort.values, [
        ThreadSort.latest,
        ThreadSort.posted,
        ThreadSort.replies,
        ThreadSort.views,
      ]);
      expect(ThreadSort.values.map((sort) => sort.label), [
        '最后发表',
        '发帖时间',
        '回复/查看',
        '查看',
      ]);
      expect(ThreadSort.latest.filter, isNull);
      expect(ThreadSort.latest.orderby, isNull);
      expect(ThreadSort.posted.filter, 'author');
      expect(ThreadSort.posted.orderby, 'dateline');
      expect(ThreadSort.replies.filter, 'reply');
      expect(ThreadSort.replies.orderby, 'replies');
      expect(ThreadSort.views.filter, 'reply');
      expect(ThreadSort.views.orderby, 'views');
      expect(ThreadSort.fallback, ThreadSort.latest);
    });
  });

  group('仓库排序参数透传', () {
    final html = File(
      'test_data/thread_list_synthetic.html',
    ).readAsStringSync();

    for (final sort in ThreadSort.values) {
      for (final typeid in [null, 1010]) {
        test('${sort.name}, typeid=$typeid 保留排序、页码和刷新参数', () async {
          final client = _RecordingClient(html);
          final repository = ForumRepository(client);
          final result = await repository.threadList(
            290,
            page: 2,
            typeid: typeid,
            filter: sort.filter,
            orderby: sort.orderby,
            refresh: true,
          );
          final params = client.requestedUrl!.queryParameters;
          expect(params['fid'], '290');
          expect(params['page'], '2');
          expect(params['filter'], typeid == null ? sort.filter : 'typeid');
          expect(params['typeid'], typeid?.toString());
          expect(params['orderby'], sort.orderby);
          expect(client.requestedRefresh, isTrue);
          expect(result.threads, isNotEmpty);
        });
      }
    }
  });

  group('用户 UID 提取', () {
    test('认伪静态与查询串两种形态', () {
      expect(ChhUrls.uidFromUrl('space-uid-12345.html'), '12345');
      expect(ChhUrls.uidFromUrl('home.php?mod=space&uid=678'), '678');
    });

    test('touid 这类参数不能误判为 uid', () {
      expect(ChhUrls.uidFromUrl('home.php?mod=space&do=pm&touid=777'), isNull);
    });
  });
}
