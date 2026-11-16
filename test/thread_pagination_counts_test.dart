import 'package:chh_app/design/theme.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/thread_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ThreadDetail _page(int page, {int? views, int? replies, bool more = true}) =>
    ThreadDetail(
      tid: 123,
      title: '分页统计',
      viewCount: views,
      replyCount: replies,
      posts: [
        Post(
          pid: page,
          floor: page,
          author: '作者',
          timeRaw: '',
          content: [TextBlock(List.filled(100, '正文$page').join('\n'))],
        ),
      ],
      page: PageInfo(current: page, hasNext: more),
    );

Future<void> _mount(WidgetTester tester, List<ThreadDetail> pages) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      home: ThreadDetailPage(
        tid: 123,
        title: '',
        loadPage: (page, _, _) async => pages[page - 1],
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _nextPage(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

void main() {
  testWidgets(
    'pagination retains omitted counts and accepts newer zero counts',
    (tester) async {
      await _mount(tester, [
        _page(1, views: 1234, replies: 56),
        _page(2),
        _page(3, views: 1300),
        _page(4, replies: 0, more: false),
      ]);
      expect(find.text('1234 查看　56 回复'), findsOneWidget);
      await _nextPage(tester);
      expect(find.text('1234 查看　56 回复'), findsOneWidget);
      await _nextPage(tester);
      expect(find.text('1300 查看　56 回复'), findsOneWidget);
      await _nextPage(tester);
      expect(find.text('1300 查看　0 回复'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'missing counts stay absent until an authoritative page returns them',
    (tester) async {
      await _mount(tester, [
        _page(1),
        _page(2, replies: 7),
        _page(3, more: false),
      ]);
      expect(find.textContaining(' 查看'), findsNothing);
      expect(find.text('7 回复'), findsNothing);
      await _nextPage(tester);
      expect(find.text('7 回复'), findsOneWidget);
      await _nextPage(tester);
      expect(find.text('7 回复'), findsOneWidget);
      expect(find.textContaining(' 查看'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
