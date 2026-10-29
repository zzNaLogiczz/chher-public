import 'dart:async';

import 'package:chh_app/data/forum_repository.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/pages/forum_threads_page.dart';
import 'package:chh_app/ui/chrome_button.dart';
import 'package:chh_app/ui/picker.dart';
import 'package:chh_app/ui/plain_rows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Request = ({
  int fid,
  int page,
  int? typeid,
  String? filter,
  String? orderby,
});

class _Forums extends ForumRepository {
  _Forums() : super(ChhClient(fetchers: []));
  final requests = <_Request>[];
  Completer<ThreadListPage>? pending;
  bool paginate = false;

  @override
  Future<List<ThreadType>> threadTypes(int fid, {bool refresh = false}) async =>
      const [ThreadType(typeid: 1010, name: '硬件')];

  @override
  Future<ThreadListPage> threadList(
    int fid, {
    int page = 1,
    int? typeid,
    String? filter,
    String? orderby,
    bool refresh = false,
  }) async {
    requests.add((
      fid: fid,
      page: page,
      typeid: typeid,
      filter: filter,
      orderby: orderby,
    ));
    if (pending != null && orderby == null) return pending!.future;
    return ThreadListPage(
      threads: [
        if (orderby == null && page == 1)
          const ThreadSummary(
            tid: 1,
            title: '置顶主题',
            author: 'reader',
            replies: 2,
            views: 12,
            sticky: true,
          ),
        for (var i = 0; i < (paginate ? 20 : 2); i++)
          ThreadSummary(
            tid: page * 100 + i,
            title: '${orderby ?? 'default'} 主题 $page-$i',
            author: 'reader',
            replies: 2,
            views: 12,
          ),
      ],
      page: PageInfo(current: page, hasNext: paginate && page == 1),
    );
  }
}

Future<void> _mount(
  WidgetTester tester,
  _Forums repo,
  int fid, {
  bool narrow = false,
}) async {
  await tester.binding.setSurfaceSize(Size(narrow ? 320 : 390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(narrow ? 2 : 1)),
        child: child!,
      ),
      home: ForumThreadsPage(
        key: ValueKey(fid),
        fid: fid,
        title: '硬件讨论',
        repository: repo,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ChromeGroupItem _sort(WidgetTester tester) => tester
    .widget<ChromeGroup>(find.byType(ChromeGroup))
    .items
    .firstWhere((item) => item.tooltip == '排序');

Future<void> _pick(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('排序'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('default sort is unselected and precedes search and compose', (
    tester,
  ) async {
    final repo = _Forums();
    await _mount(tester, repo, 1101);
    expect(_sort(tester).selected, isFalse);
    expect(
      tester
          .widget<ChromeGroup>(find.byType(ChromeGroup))
          .items
          .map((i) => i.tooltip),
      ['排序', '搜索帖子', '发主题'],
    );
    expect(repo.requests.single.orderby, isNull);
  });

  testWidgets('reply sort selects the icon and sends site parameters', (
    tester,
  ) async {
    final repo = _Forums();
    await _mount(tester, repo, 1102);
    await _pick(tester, '回复/查看');
    expect(_sort(tester).selected, isTrue);
    expect(repo.requests.last.filter, 'reply');
    expect(repo.requests.last.orderby, 'replies');
    final count = repo.requests.length;
    await _pick(tester, '回复/查看');
    expect(repo.requests.length, count);
  });

  testWidgets('category and sort are retained in both directions', (
    tester,
  ) async {
    final repo = _Forums();
    await _mount(tester, repo, 1103);
    await tester.tap(find.byType(PickerButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('硬件').last);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    await _pick(tester, '查看');
    expect(repo.requests.last.typeid, 1010);
    expect(repo.requests.last.orderby, 'views');
    await tester.tap(find.byType(PickerButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部分类').last);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(repo.requests.last.typeid, isNull);
    expect(repo.requests.last.orderby, 'views');
  });

  testWidgets('dismissing sheet leaves requests and selection unchanged', (
    tester,
  ) async {
    final repo = _Forums();
    await _mount(tester, repo, 1104);
    await _pick(tester, '发帖时间');
    expect(repo.requests.last.filter, 'author');
    expect(repo.requests.last.orderby, 'dateline');
    final count = repo.requests.length;
    await tester.tap(find.byTooltip('排序'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(repo.requests.length, count);
    expect(_sort(tester).selected, isTrue);
  });

  testWidgets('sort memory survives route recreation and isolates fid', (
    tester,
  ) async {
    final repo = _Forums();
    await _mount(tester, repo, 1105);
    await _pick(tester, '查看');
    await _mount(tester, repo, 1106);
    expect(_sort(tester).selected, isFalse);
    expect(repo.requests.last.orderby, isNull);
    await _mount(tester, repo, 1105);
    expect(_sort(tester).selected, isTrue);
    expect(repo.requests.last.orderby, 'views');
  });

  testWidgets('page two preserves selected sort parameters', (tester) async {
    final repo = _Forums()..paginate = true;
    await _mount(tester, repo, 1107);
    await tester.tap(find.byType(PickerButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('硬件').last);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    await _pick(tester, '回复/查看');
    for (
      var i = 0;
      i < 8 && !repo.requests.any((r) => r.page == 2 && r.orderby == 'replies');
      i++
    ) {
      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await tester.pumpAndSettle();
    }
    expect(
      repo.requests.where(
        (r) =>
            r.page == 2 &&
            r.typeid == 1010 &&
            r.filter == 'reply' &&
            r.orderby == 'replies',
      ),
      hasLength(1),
    );
  });

  testWidgets('pinned group follows returned data and restores on default', (
    tester,
  ) async {
    final repo = _Forums();
    await _mount(tester, repo, 1108);
    expect(find.byType(PinnedGroupRow), findsOneWidget);
    await _pick(tester, '查看');
    expect(find.byType(PinnedGroupRow), findsNothing);
    await _pick(tester, '最后发表');
    expect(find.byType(PinnedGroupRow), findsOneWidget);
    expect(_sort(tester).selected, isFalse);
  });

  testWidgets('changing sort discards a late default response', (tester) async {
    final repo = _Forums()..pending = Completer<ThreadListPage>();
    await _mount(tester, repo, 1109);
    await _pick(tester, '查看');
    repo.pending!.complete(
      const ThreadListPage(
        threads: [
          ThreadSummary(
            tid: 900,
            title: '过期结果',
            author: 'reader',
            replies: 0,
            views: 0,
          ),
        ],
        page: PageInfo(current: 1, hasNext: false),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('过期结果'), findsNothing);
    expect(find.text('views 主题 1-0'), findsOneWidget);
  });

  testWidgets(
    '320dp at 2x keeps all four labels readable and actions at least 44dp',
    (tester) async {
      await _mount(tester, _Forums(), 1110, narrow: true);
      for (final tooltip in ['排序', '搜索帖子', '发主题']) {
        final size = tester.getSize(find.byTooltip(tooltip));
        expect(size.width, greaterThanOrEqualTo(44));
        expect(size.height, greaterThanOrEqualTo(44));
      }
      await tester.tap(find.byTooltip('排序'));
      await tester.pumpAndSettle();
      expect(find.text('排序方式'), findsOneWidget);
      for (final (index, label) in ['最后发表', '发帖时间', '回复/查看', '查看'].indexed) {
        final text = tester.widget<Text>(find.text(label));
        expect(text.maxLines, isNull);
        expect(text.overflow, isNull);
        final size = tester.getSize(
          find.byKey(ValueKey('picker-option-$index')),
        );
        expect(size.width, greaterThanOrEqualTo(44));
        expect(size.height, greaterThanOrEqualTo(44));
      }
      expect(tester.takeException(), isNull);
    },
  );
}
