import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:chh_app/controllers/article_reader_controller.dart';
import 'package:chh_app/models/models.dart';

ArticleContent page(int number, {bool hasNext = true, String? text}) =>
    ArticleContent(
      ArticleDetail(
        aid: 1,
        title: '评测',
        content: [TextBlock(text ?? '正文$number')],
        page: PageInfo(current: number, hasNext: hasNext),
      ),
    );

void main() {
  test('appends real pages in order and stops at the end', () async {
    final calls = <int>[];
    final reader = ArticleReaderController(
      loadPage: (n, refresh) async {
        calls.add(n);
        return page(n, hasNext: n < 3);
      },
    );
    await reader.loadNext();
    final first = reader.pages.first;
    await reader.loadNext();
    await reader.loadNext();
    await reader.loadNext();
    expect(calls, [1, 2, 3]);
    expect(reader.pages.first, same(first));
    expect(reader.pages.map((p) => p.page.current), [1, 2, 3]);
    expect(reader.hasNext, isFalse);
    reader.dispose();
  });

  test('overlapping scroll signals share one in-flight page', () async {
    final pending = Completer<PortalContent>();
    var calls = 0;
    final reader = ArticleReaderController(
      loadPage: (n, refresh) {
        calls++;
        return pending.future;
      },
    );
    final first = reader.loadNext();
    await reader.loadNext();
    await reader.loadNext();
    expect(calls, 1);
    expect(reader.isLoading, isTrue);
    pending.complete(page(1));
    await first;
    expect(reader.pages.length, 1);
    reader.dispose();
  });

  test('failed continuation keeps existing text and waits for retry', () async {
    final calls = <(int, bool)>[];
    var fail = true;
    final reader = ArticleReaderController(
      loadPage: (n, refresh) async {
        calls.add((n, refresh));
        if (n == 2 && fail) throw StateError('offline');
        return page(n, hasNext: n < 2);
      },
    );
    await reader.loadNext();
    await reader.loadNext();
    await reader.loadNext();
    expect(reader.pages.length, 1);
    expect(reader.error, isNotNull);
    expect(calls, [(1, false), (2, false)]);
    fail = false;
    await reader.retry();
    expect(calls.last, (2, true));
    expect(reader.pages.length, 2);
    expect(reader.error, isNull);
    reader.dispose();
  });

  test('source fallback to page one is never appended in a loop', () async {
    final reader = ArticleReaderController(
      loadPage: (n, refresh) async => page(1),
    );
    await reader.loadNext();
    await reader.loadNext();
    await reader.loadNext();
    expect(reader.pages.length, 1);
    expect(reader.error, isA<ArticleContinuationException>());
    reader.dispose();
  });

  test(
    'identical content with an incremented page number is rejected',
    () async {
      final reader = ArticleReaderController(
        loadPage: (n, refresh) async => page(n, text: 'same'),
      );
      await reader.loadNext();
      await reader.loadNext();
      expect(reader.pages.length, 1);
      expect(reader.error, isA<ArticleContinuationException>());
      reader.dispose();
    },
  );

  test(
    'late response after leaving the reader does not notify or append',
    () async {
      final pending = Completer<PortalContent>();
      var notices = 0;
      final reader = ArticleReaderController(
        loadPage: (n, refresh) => pending.future,
      );
      reader.addListener(() => notices++);
      final request = reader.loadNext();
      reader.dispose();
      pending.complete(page(1));
      await request;
      expect(notices, 1);
      expect(reader.pages, isEmpty);
    },
  );

  test(
    'forum landing page is handed off without treating it as article text',
    () async {
      var calls = 0;
      final reader = ArticleReaderController(
        loadPage: (n, refresh) async {
          calls++;
          return const ThreadContent(42, '论坛原文');
        },
      );
      await reader.loadNext();
      await reader.loadNext();
      expect(reader.thread?.tid, 42);
      expect(reader.pages, isEmpty);
      expect(calls, 1);
      reader.dispose();
    },
  );
}
