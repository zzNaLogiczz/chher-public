import 'dart:io';

import 'package:chh_app/design/theme.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/source_page_drawer.dart';
import 'package:chh_app/pages/thread_detail_page.dart';
import 'package:chh_app/parser/portal_parser.dart';
import 'package:chh_app/parser/thread_parser.dart';
import 'package:chh_app/ui/chrome_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('眉题来自面包屑', () {
    test('帖子取最深的版块,不取分区', () {
      final detail = parseThread(
        File('test_data/thread_synthetic.html').readAsStringSync(),
        tid: 900001,
      );
      expect(detail.forumName, '示例装机区');
    });

    test('文章取最深的栏目', () {
      final article = parseArticle('''
<html><body>
<div id="pt" class="bm cl"><div class="z">
  <a href="./" class="nvhm">Chiphell</a><em>›</em>
  <a href="portal.php">门户</a><em>›</em>
  <a href="https://www.chiphell.com/portal.php?mod=list&amp;catid=1">评测</a><em>›</em>
  <a href="https://www.chiphell.com/portal.php?mod=list&amp;catid=30">显卡</a><em>›</em>
  查看内容
</div></div>
<div class="vw"><div class="h"><h1 class="ph">示例评测</h1></div></div>
<td id="article_content"><p>正文</p></td>
</body></html>''', aid: 1);
      expect(article.categoryName, '显卡');
    });
  });

  test('手机版原页面地址', () {
    expect(
      threadSourceUrl(123, page: 2).toString(),
      'https://www.chiphell.com/forum.php?mod=viewthread&tid=123&page=2&mobile=2',
    );
    expect(articleSourceUrl(9).queryParameters['mobile'], '2');
  });

  Future<void> pumpThread(WidgetTester tester, {String? forumName}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: ThreadDetailPage(
          tid: 1,
          title: '示例',
          loadPage: (page, _, _) async => ThreadDetail(
            tid: 1,
            fid: 312,
            forumName: forumName,
            title: '示例',
            posts: const [
              Post(
                pid: 10,
                floor: 1,
                author: '楼主',
                authorUid: '10',
                timeRaw: '',
                content: [TextBlock('正文')],
              ),
            ],
            page: const PageInfo(current: 1, hasNext: false),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('帖子左上角显示所在版块,不再固定写社区讨论', (tester) async {
    await pumpThread(tester, forumName: '自由水世界2024');
    expect(find.text('自由水世界2024'), findsOneWidget);
    expect(find.text('社区讨论'), findsNothing);
  });

  testWidgets('读不到版块时不显示占位眉题', (tester) async {
    await pumpThread(tester);
    expect(find.text('社区讨论'), findsNothing);
  });

  testWidgets('右上角常驻原页面按钮,点开是抽屉,关闭回到帖子', (tester) async {
    await pumpThread(tester, forumName: '自由水世界2024');
    await tester.tap(find.byKey(const ValueKey('thread-source-page')));
    // 只推进到滑入途中:网页要等抽屉停稳才创建,测试环境没有原生网页实现
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byType(SourcePageDrawer), findsOneWidget);
    // 抽屉还在滑入,关闭钮在屏幕外,直接触发它的回调
    tester
        .widget<ChromeButton>(
          find.byWidgetPredicate(
            (w) => w is ChromeButton && w.tooltip == '关闭原页面',
          ),
        )
        .onPressed!();
    await tester.pumpAndSettle();
    expect(find.byType(SourcePageDrawer), findsNothing);
    expect(find.text('自由水世界2024'), findsOneWidget);
  });
}
