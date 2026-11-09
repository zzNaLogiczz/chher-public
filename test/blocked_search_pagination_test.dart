import 'package:chh_app/data/user_block_index.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/search_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'a fully blocked first search page keeps its next source page reachable',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const blockedUid = '999107';
      await tester.runAsync(
        () => userBlockIndex.block(uid: blockedUid, name: '已屏蔽作者'),
      );
      addTearDown(() async {
        await tester.runAsync(() => userBlockIndex.unblock(blockedUid));
      });
      var nextCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: SearchPage(
            initialQuery: '硬件',
            search: (_) async => const SearchResultPage(
              rows: [
                ThreadSummary(
                  tid: 10,
                  title: '不可显示的首屏帖子',
                  author: '已屏蔽作者',
                  authorUid: blockedUid,
                  replies: 0,
                  views: 0,
                ),
              ],
              page: PageInfo(current: 1, hasNext: true),
              nextUrl:
                  'https://www.chiphell.com/search.php?searchid=fixture&page=2',
            ),
            searchNext: (previous) async {
              expect(previous.page.current, 1);
              expect(previous.rows.single.tid, 10);
              nextCalls++;
              return const SearchResultPage(
                rows: [
                  ThreadSummary(
                    tid: 11,
                    title: '第二页的可见帖子',
                    author: '其他作者',
                    authorUid: '999108',
                    replies: 0,
                    views: 0,
                  ),
                ],
                page: PageInfo(current: 2, hasNext: false),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('不可显示的首屏帖子'), findsNothing);
      expect(find.text('已隐藏黑名单用户的帖子'), findsOneWidget);
      await tester.tap(find.text('继续加载'));
      await tester.pumpAndSettle();
      expect(nextCalls, 1);
      expect(find.text('第二页的可见帖子'), findsOneWidget);
      expect(find.text('不可显示的首屏帖子'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
