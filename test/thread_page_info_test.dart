import 'package:chh_app/parser/thread_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'notice landing uses the actual source page instead of request fallback',
    () {
      final detail = parseThread(
        '<div class="pg"><strong>4</strong><a class="nxt">下一页</a></div>',
        tid: 42,
        fallbackPage: 1,
      );
      expect(detail.page.current, 4);
      expect(detail.page.hasNext, isTrue);
    },
  );
  test('autopbn current page is respected when no pager is visible', () {
    final detail = parseThread(
      '<a id="autopbn" curpage="3" totalpage="6"></a>',
      tid: 42,
    );
    expect(detail.page.current, 3);
    expect(detail.page.hasNext, isTrue);
  });
  test(
    'absent pagination retains the requested fallback without inventing a next page',
    () {
      final detail = parseThread(
        '<h1 id="thread_subject">帖</h1>',
        tid: 42,
        fallbackPage: 7,
      );
      expect(detail.page.current, 7);
      expect(detail.page.hasNext, isFalse);
    },
  );
}
