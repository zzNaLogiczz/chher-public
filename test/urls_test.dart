/// URL 构造单测
///
/// 回归用:帖子详情的伪静态把页码写到了第 3 段(那是 authorid),
/// 导致任何页码都取回第 1 页,表现为能一直翻页但内容不变。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:chh_app/core/chh_urls.dart';

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

    test('typeid 为 0 视为不筛选', () {
      final u = ChhUrls.threadListFiltered(290, typeid: 0);
      expect(u.queryParameters.containsKey('typeid'), isFalse);
    });
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
