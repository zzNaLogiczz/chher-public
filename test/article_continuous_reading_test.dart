import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/article_page.dart';

ArticleContent _page(int number, {bool hasNext = false}) => ArticleContent(
  ArticleDetail(
    aid: 99,
    title: '连续评测',
    content: [TextBlock('这是第$number段正文')],
    page: PageInfo(current: number, hasNext: hasNext),
  ),
);

void main() {
  testWidgets('short source pages unfold automatically without page controls', (
    tester,
  ) async {
    final calls = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: ArticlePage(
          aid: 99,
          title: '连续评测',
          loadPage: (page, refresh) async {
            calls.add(page);
            return _page(page, hasNext: page < 3);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, [1, 2, 3]);
    expect(find.text('这是第1段正文'), findsOneWidget);
    expect(find.text('这是第2段正文'), findsOneWidget);
    expect(find.text('这是第3段正文'), findsOneWidget);
    expect(find.byTooltip('下一页'), findsNothing);
    expect(find.byTooltip('上一页'), findsNothing);
    expect(find.text('跳转到页码'), findsNothing);
    // 底部阅读工具栏:写评论输入胶囊 + 评论圆钮
    expect(find.text('写评论…'), findsOneWidget);
    expect(find.byTooltip('查看评论'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'continuation failure leaves text in place and exposes one retry',
    (tester) async {
      var fail = true;
      final calls = <(int, bool)>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: ArticlePage(
            aid: 99,
            title: '连续评测',
            loadPage: (page, refresh) async {
              calls.add((page, refresh));
              if (page == 2 && fail) throw StateError('offline');
              return _page(page, hasNext: page < 2);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('这是第1段正文'), findsOneWidget);
      expect(find.text('后续内容暂时无法加载'), findsOneWidget);
      expect(calls, [(1, false), (2, false)]);
      fail = false;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('这是第1段正文'), findsOneWidget);
      expect(find.text('这是第2段正文'), findsOneWidget);
      expect(calls.last, (2, true));
      expect(tester.takeException(), isNull);
    },
  );
}
