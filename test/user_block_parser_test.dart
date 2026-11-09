import 'package:flutter_test/flutter_test.dart';
import 'package:chh_app/parser/thread_list_parser.dart';
import 'package:chh_app/parser/guide_parser.dart';
import 'package:chh_app/parser/search_result_parser.dart';

void main() {
  test('board reads original author UID, never the last reply author', () {
    final page = parseThreadList(
      '''<table><tbody id="normalthread_10"><tr><th><a class="xst">讨论</a></th><td class="by"><cite><a href="space-uid-42.html">作者</a></cite></td><td class="by"><cite><a href="space-uid-99.html">最后回复者</a></cite></td></tr></tbody></table>''',
    );
    expect(page.threads.single.authorUid, '42');
  });
  test('missing original author UID stays unknown despite last reply link', () {
    final page = parseThreadList(
      '''<table><tbody id="normalthread_10"><tr><th><a class="xst">讨论</a></th><td class="by"><cite><a>作者</a></cite></td><td class="by"><cite><a href="space-uid-99.html">末回复</a></cite></td></tr></tbody></table>''',
    );
    expect(page.threads.single.authorUid, isNull);
  });
  test('guide skips forum cell and extracts author from second by cell', () {
    final page = parseGuide(
      '''<table><tbody id="normalthread_10"><tr><th><a class="xst">讨论</a></th><td class="by"><a href="forum-146-1.html">版块</a></td><td class="by"><cite><a href="home.php?mod=space&amp;uid=42">作者</a></cite></td></tr></tbody></table>''',
    );
    expect(page.threads.single.authorUid, '42');
  });
  test('search extracts UID from metadata, not quoted snippet author', () {
    final page = parseSearchResult(
      '''<div id="threadlist"><ul><li class="pbw" id="10"><h3><a href="forum.php?mod=viewthread&amp;tid=10">讨论</a></h3><p class="xg1">1 个回复 - 2 次查看</p><p><a href="space-uid-99.html">摘要引用用户</a></p><p><span>2026-01-01</span><a href="space-uid-42.html">作者</a></p></li></ul></div>''',
    );
    expect(page.rows.single.authorUid, '42');
  });
}
