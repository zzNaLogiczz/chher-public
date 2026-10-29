import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/models/article_discussion.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/article_discussion_page.dart';
import 'package:chh_app/ui/sheet_scaffold.dart';
import 'package:chh_app/widgets/article_discussion_widgets.dart';
import 'package:chh_app/widgets/comment_mode_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smooth_sheets/smooth_sheets.dart';

Widget _app(Widget child, {bool large = false}) => MaterialApp(
  theme: buildAppTheme(large ? Brightness.dark : Brightness.light),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(large ? 1.6 : 1)),
    child: child!,
  ),
  home: child,
);

const _quote = QuoteBlock([
  TextBlock('这段引用比较长，用来确认初始展示的是两行摘要，而完整正文只在明确展开后出现。'),
  TextBlock('展开后的独立尾段'),
], source: '被引用的评论');

const _discussion = ArticleDiscussion(
  aid: 50001,
  title: '示例硬件评测',
  total: 14,
  page: PageInfo(current: 1, hasNext: false),
  items: [
    ArticleComment(
      cid: 7002,
      author: '测试读者甲',
      timeRaw: '2001-01-02 09:30',
      text: '配置讨论',
      content: [TextBlock('配置讨论')],
    ),
  ],
);

void main() {
  testWidgets(
    'quoted context expands on demand and collapses to its original height',
    (tester) async {
      await tester.pumpWidget(
        _app(
          const Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: DiscussionQuote(quote: _quote),
              ),
            ),
          ),
        ),
      );
      final collapsed = tester.getSize(find.byType(DiscussionQuote)).height;
      expect(find.text('展开后的独立尾段'), findsNothing);
      await tester.tap(find.text('展开引用'));
      await tester.pumpAndSettle();
      expect(find.text('展开后的独立尾段'), findsOneWidget);
      expect(
        tester.getSize(find.byType(DiscussionQuote)).height,
        greaterThan(collapsed),
      );
      await tester.tap(find.text('收起引用'));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(DiscussionQuote)).height,
        closeTo(collapsed, .5),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('quote direction can be reversed before the spring settles', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: DiscussionQuote(quote: _quote),
            ),
          ),
        ),
      ),
    );
    final collapsed = tester.getSize(find.byType(DiscussionQuote)).height;
    await tester.tap(find.text('展开引用'));
    await tester.pump(const Duration(milliseconds: 32));
    await tester.tap(find.text('收起引用'));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(DiscussionQuote)).height,
      closeTo(collapsed, .5),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'narrow dark large-type layout keeps the count and composition action reachable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        _app(
          ArticleDiscussionPage(
            aid: 50001,
            title: _discussion.title,
            isLoggedIn: () => false,
            loadPage: (_, _) async => _discussion,
          ),
          large: true,
        ),
      );
      await tester.pumpAndSettle();
      final action = tester.getRect(
        find.byKey(const ValueKey('discussion-write-action')),
      );
      expect(find.byKey(const ValueKey('discussion-context')), findsNothing);
      expect(action.left, greaterThanOrEqualTo(0));
      expect(action.right, lessThanOrEqualTo(320));
      expect(action.height, greaterThanOrEqualTo(44));
      expect(find.text('14'), findsOneWidget);
      expect(find.text('登录后参与讨论'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'new reply action preserves the source cid and retains its draft after dismissal',
    (tester) async {
      int? submittedCid;
      await tester.pumpWidget(
        _app(
          ArticleDiscussionPage(
            aid: 50001,
            title: _discussion.title,
            isLoggedIn: () => true,
            loadPage: (_, _) async => _discussion,
            submitReply: (message, target) async {
              submittedCid = target?.cid;
              return const PostResult(PostResultKind.failed, '站点暂不可用');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('回复').first);
      await tester.pumpAndSettle();
      expect(find.text('回复给 测试读者甲'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '新的回复草稿');
      await tester.pumpAndSettle();
      await tester.tap(find.text('发送'));
      await tester.pumpAndSettle();
      expect(submittedCid, 7002);
      expect(find.text('站点暂不可用'), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('回复').first);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '新的回复草稿',
      );
      expect(tester.takeException(), isNull);
    },
  );

  Future<void> openSheet(
    WidgetTester tester, {
    Future<ArticleDiscussion> Function(int page, bool refresh)? loadPage,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => ArticleDiscussionPage.show(
                context,
                aid: 50001,
                title: _discussion.title,
                isLoggedIn: () => true,
                loadPage:
                    loadPage ??
                    ((_, _) async => ArticleDiscussion(
                      aid: 50001,
                      title: _discussion.title,
                      total: 30,
                      page: const PageInfo(current: 1, hasNext: false),
                      items: [
                        for (var i = 0; i < 30; i++)
                          ArticleComment(
                            cid: i + 1,
                            author: '读者 $i',
                            text: '第 $i 条离线布局评论。',
                          ),
                      ],
                    )),
                submitReply: (_, _) async =>
                    const PostResult(PostResultKind.failed, '离线测试不发送'),
              ),
              child: const Text('查看讨论'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('查看讨论'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'sheet follows spec: header count, one context line, fill capsule',
    (tester) async {
      await openSheet(tester);
      // 上下文只在头部占一行,不再有大卡和正文里的"文章评论"标题
      expect(find.byKey(const ValueKey('discussion-context')), findsNothing);
      expect(find.text(_discussion.title), findsOneWidget);
      expect(find.text('文章评论'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(SheetHeader),
          matching: find.text('评论'),
        ),
        findsOneWidget,
      );
      expect(find.text('30'), findsOneWidget);
      // 查看方式与帖子同一个控件;认不出作者时只有两段
      expect(find.byType(CommentModeBar), findsOneWidget);
      expect(find.text('原楼层'), findsOneWidget);
      expect(find.text('只看作者'), findsNothing);
      // 底部是 fill 底的"写评论…"输入胶囊
      final action = find.byKey(const ValueKey('discussion-write-action'));
      expect(
        find.descendant(of: action, matching: find.text('写评论…')),
        findsOneWidget,
      );
      final capsule = tester
          .widgetList<DecoratedBox>(
            find.descendant(of: action, matching: find.byType(DecoratedBox)),
          )
          .map((b) => b.decoration)
          .whereType<BoxDecoration>()
          .firstWhere((d) => d.borderRadius == BorderRadius.circular(22));
      expect(capsule.color, AppTokens.light.fill);
      // 评论与帖子评论同样式:圆形头像、浅色"回复"文字
      final tile = find.byType(ArticleCommentTile).first;
      expect(
        find.descendant(of: tile, matching: find.byType(ClipOval)),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(find.descendant(of: tile, matching: find.text('回复')))
            .style!
            .color,
        AppTokens.light.text2,
      );
    },
  );

  testWidgets(
    'real modal sheet opens partially and keeps composition visible through full expansion',
    (tester) async {
      await openSheet(tester);
      final sheet = find.byType(SheetContentScaffold).first;
      final action = find.byKey(const ValueKey('discussion-write-action'));
      final initialTop = tester.getRect(sheet).top;
      expect(initialTop, greaterThan(150));
      expect(initialTop, lessThan(450));
      expect(tester.getRect(action).bottom, lessThanOrEqualTo(844));
      expect(action.hitTestable(), findsOneWidget);
      // 展开按钮已去掉:拖动顶部拖动条展开到全屏档
      await tester.drag(
        find.byKey(const ValueKey('discussion-sheet-grip')),
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(sheet).top, lessThan(initialTop - 150));
      expect(tester.getRect(action).bottom, lessThanOrEqualTo(844));
      expect(action.hitTestable(), findsOneWidget);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dragging the sheet header expands it before list scrolling takes over',
    (tester) async {
      await openSheet(tester);
      final sheet = find.byType(SheetContentScaffold).first;
      final before = tester.getRect(sheet).top;
      await tester.drag(
        find.byKey(const ValueKey('discussion-sheet-grip')),
        const Offset(0, -450),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(sheet).top, lessThan(before - 150));
      final list = find.byType(CustomScrollView).first;
      await tester.drag(list, const Offset(0, -350));
      await tester.pumpAndSettle();
      final scroll = tester.state<ScrollableState>(
        find.descendant(of: list, matching: find.byType(Scrollable)).first,
      );
      expect(scroll.position.pixels, greaterThan(0));
      expect(tester.getRect(sheet).top, lessThan(80));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the sheet scroll controller still triggers automatic comment pagination',
    (tester) async {
      final reads = <int>[];
      await openSheet(
        tester,
        loadPage: (page, refresh) async {
          reads.add(page);
          return ArticleDiscussion(
            aid: 50001,
            title: _discussion.title,
            page: PageInfo(current: page, hasNext: page == 1),
            items: page == 1
                ? [
                    for (var i = 1; i <= 12; i++)
                      ArticleComment(
                        cid: i,
                        author: '读者 $i',
                        text: '用于验证顺序追加的评论 $i。',
                      ),
                  ]
                : const [
                    ArticleComment(
                      cid: 13,
                      author: '读者 13',
                      text: '自动加载的下一页评论',
                    ),
                  ],
          );
        },
      );
      expect(reads, [1]);
      await tester.drag(
        find.byKey(const ValueKey('discussion-sheet-grip')),
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      for (var n = 0; n < 8 && reads.length == 1; n++) {
        await tester.drag(
          find.byType(CustomScrollView).first,
          const Offset(0, -1000),
        );
        await tester.pumpAndSettle();
      }
      expect(reads, [1, 2]);
      expect(tester.takeException(), isNull);
    },
  );
}
