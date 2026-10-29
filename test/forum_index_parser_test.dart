import 'dart:io';

import 'package:chh_app/parser/forum_index_parser.dart';
import 'package:flutter_test/flutter_test.dart';

String _forum(int id, String name) =>
    '''
<table><tr><td class="fl_g"><dl>
<dt><a href="forum-$id-1.html">$name</a></dt>
<dd><em>主题: 12</em></dd>
</dl></td></tr></table>
''';

String _category(String name, String body) =>
    '''
<div class="bm bmw"><div class="bm_h"><h2><a href="forum.php?gid=1">$name</a></h2></div>
<div class="bm_c">$body</div></div>
''';

void main() {
  test(
    'synthetic outer fl.bm does not duplicate its first category or forums',
    () {
      final categories = parseForumIndex(
        File('test_data/forum_index_synthetic.html').readAsStringSync(),
      );
      final forums = categories.expand((category) => category.forums).toList();
      expect(categories, hasLength(4));
      expect(forums, hasLength(10));
      for (final id in [101, 102, 103]) {
        expect(forums.where((forum) => forum.fid == id), hasLength(1));
      }
      expect(categories.first.name, '示例活动区');
      expect(categories.last.name, '管理分区');
    },
  );

  test('same-named real category blocks retain their own memberships', () {
    final categories = parseForumIndex(
      '<div class="fl bm">${_category('同名分区', _forum(1, '版块甲'))}${_category('同名分区', _forum(2, '版块乙'))}</div>',
    );
    expect(categories, hasLength(2));
    expect(categories.map((category) => category.name), ['同名分区', '同名分区']);
    expect(categories[0].forums.single.fid, 1);
    expect(categories[1].forums.single.fid, 2);
  });

  test('an inner category is not borrowed by an outer category body', () {
    final categories = parseForumIndex(
      _category(
        '父分区',
        '${_forum(1, '父版块')}${_category('子分区', _forum(2, '子版块'))}',
      ),
    );
    expect(categories, hasLength(2));
    expect(categories[0].forums.map((forum) => forum.fid), [1]);
    expect(categories[1].forums.map((forum) => forum.fid), [2]);
  });
}
