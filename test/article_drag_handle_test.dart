import 'package:chh_app/design/theme.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/article_page.dart';
import 'package:chh_app/widgets/editorial_article_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'first accepted handle movement includes distance from touch down',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    EditorialArticleRoute(
                      builder: (_) => ArticlePage(
                        aid: 99,
                        title: '读图',
                        preview: const PortalArticle(
                          aid: 99,
                          title: '读图',
                          coverUrl: 'https://example.invalid/image.jpg',
                        ),
                        loadPage: (page, refresh) async => const ArticleContent(
                          ArticleDetail(
                            aid: 99,
                            title: '读图',
                            content: [TextBlock('正文')],
                            page: PageInfo(current: 1, hasNext: false),
                          ),
                        ),
                      ),
                    ),
                  ),
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      final before = tester.getTopLeft(find.byTooltip('关闭文章')).dy;
      final pointer = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('article-dismiss-handle'))),
      );
      await pointer.moveBy(const Offset(0, 200));
      await tester.pump();
      final after = tester.getTopLeft(find.byTooltip('关闭文章')).dy;
      expect(after - before, closeTo(200, 2));
      await pointer.up();
      await tester.pumpAndSettle();
      expect(find.text('打开'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
