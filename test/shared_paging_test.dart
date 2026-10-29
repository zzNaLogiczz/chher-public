import 'dart:async';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/widgets/sliver_paged_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget harness(
  GlobalKey<SliverPagedListState<String>> key,
  ScrollController scroll,
  Future<Paged<String>> Function(int page, {bool refresh}) loader,
) => MaterialApp(
  theme: buildAppTheme(Brightness.light),
  home: Scaffold(
    body: CustomScrollView(
      controller: scroll,
      slivers: [
        SliverPagedList<String>(
          key: key,
          controller: scroll,
          loader: loader,
          itemKey: (item) => item,
          itemBuilder: (_, text) => SizedBox(height: 90, child: Text(text)),
        ),
      ],
    ),
  ),
);

void main() {
  testWidgets('rows own their insets: the list adds no side padding or rules', (
    tester,
  ) async {
    final scroll = ScrollController();
    await tester.pumpWidget(
      harness(
        GlobalKey<SliverPagedListState<String>>(),
        scroll,
        (page, {refresh = false}) async => const Paged(
          items: ['first', 'second'],
          page: PageInfo(current: 1, hasNext: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 行自身带 20dp 屏幕边距和分隔线,列表再加就会变成 44dp 和双线
    expect(tester.getTopLeft(find.text('first')).dx, 0);
    expect(find.byType(Divider), findsNothing);
  });

  testWidgets(
    'changing a filter cannot be overwritten by its older pending response',
    (tester) async {
      final old = Completer<Paged<String>>();
      final latest = Completer<Paged<String>>();
      var filter = 'old';
      final scroll = ScrollController();
      final key = GlobalKey<SliverPagedListState<String>>();
      await tester.pumpWidget(
        harness(
          key,
          scroll,
          (page, {refresh = false}) =>
              filter == 'old' ? old.future : latest.future,
        ),
      );
      filter = 'new';
      final refresh = key.currentState!.refresh(clear: true);
      latest.complete(
        const Paged(
          items: ['new result'],
          page: PageInfo(current: 1, hasNext: false),
        ),
      );
      await refresh;
      await tester.pumpAndSettle();
      old.complete(
        const Paged(
          items: ['stale result'],
          page: PageInfo(current: 1, hasNext: false),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('new result'), findsOneWidget);
      expect(find.text('stale result'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'continuation errors stop automatic requests and preserve existing rows',
    (tester) async {
      final calls = <int>[];
      var fail = true;
      final scroll = ScrollController();
      final key = GlobalKey<SliverPagedListState<String>>();
      await tester.pumpWidget(
        harness(key, scroll, (page, {refresh = false}) async {
          calls.add(page);
          if (page == 2 && fail) throw StateError('offline');
          return Paged(
            items: ['row$page'],
            page: PageInfo(current: page, hasNext: page < 2),
          );
        }),
      );
      await tester.pumpAndSettle();
      expect(calls, [1, 2]);
      expect(find.text('row1'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(calls, [1, 2]);
      fail = false;
      await tester.tap(find.text('加载失败，重试'));
      await tester.pumpAndSettle();
      expect(calls, [1, 2, 2]);
      expect(find.text('row1'), findsOneWidget);
      expect(find.text('row2'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
      expect(tester.takeException(), isNull);
    },
  );
}
