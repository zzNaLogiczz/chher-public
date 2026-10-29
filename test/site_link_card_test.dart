import 'dart:async';

import 'package:chh_app/core/link_target.dart';
import 'package:chh_app/data/link_preview_repository.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/widgets/site_link_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _archiver = '''
<div id="content"><p class="author"><strong>a</strong> 发表于 2026-10-19 14:41</p>
<h3>5080 公版拆机：均热板与供电布局细节</h3></div>''';

Widget _app(
  Widget child, {
  Brightness brightness = Brightness.light,
  double width = 390,
  double textScale = 1,
}) => MaterialApp(
  theme: buildAppTheme(brightness),
  home: MediaQuery(
    data: MediaQueryData(
      size: Size(width, 844),
      textScaler: TextScaler.linear(textScale),
    ),
    child: Scaffold(
      body: Center(
        child: SizedBox(width: width - 40, child: child),
      ),
    ),
  ),
);

void main() {
  late Map<String, Completer<String>> pending;
  late LinkPreviewRepository repo;
  late List<(LinkTarget, String)> opened;

  setUp(() {
    pending = {};
    opened = [];
    repo = LinkPreviewRepository(
      fetchHtml: (uri) => (pending[uri.toString()] = Completer()).future,
      openArticle: (_) async => ArticleContent(
        ArticleDetail(
          aid: 1,
          title: '2026 年秋季显卡散热器横评',
          metaRaw: '2026-9-30 10:00',
          content: const [],
          page: const PageInfo(current: 1, hasNext: false),
        ),
      ),
    );
  });

  SiteLinkCard card(String href, {String label = ''}) => SiteLinkCard(
    block: SiteLinkBlock(classifyLink(href)!, label: label),
    repository: repo,
    onOpen: (target, title) => opened.add((target, title)),
  );

  testWidgets('读取中显示链接文字，取到后显示标题、类型和日期', (tester) async {
    await tester.pumpWidget(
      _app(card('thread-2907156-1-1.html', label: '拆机帖')),
    );
    expect(find.text('拆机帖'), findsOneWidget);
    expect(find.text('帖子'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('site-card-date-placeholder')),
      findsOneWidget,
    );

    pending.values.single.complete(_archiver);
    await tester.pumpAndSettle();
    expect(find.text('5080 公版拆机：均热板与供电布局细节'), findsOneWidget);
    expect(find.text('2026-10-19'), findsOneWidget);
    expect(find.text('拆机帖'), findsNothing);
  });

  testWidgets('链接文字就是网址时，读取中显示地址末段', (tester) async {
    await tester.pumpWidget(
      _app(card('https://www.chiphell.com/thread-2907156-1-1.html')),
    );
    expect(find.text('thread-2907156-1-1.html'), findsOneWidget);
    pending.values.single.complete(_archiver);
    await tester.pumpAndSettle();
  });

  testWidgets('已缓存时首帧直接显示标题', (tester) async {
    final target = classifyLink('thread-2907156-1-1.html')!;
    final first = repo.preview(target);
    // 假时钟下用 pump 推进微任务,不能直接等真实的 Future.delayed
    await tester.pump();
    pending.values.single.complete(_archiver);
    await first;
    await tester.pumpWidget(_app(card('thread-2907156-1-1.html')));
    expect(find.text('5080 公版拆机：均热板与供电布局细节'), findsOneWidget);
    expect(pending, hasLength(1));
  });

  testWidgets('读取失败保留链接文字，只显示类型，仍可点击', (tester) async {
    await tester.pumpWidget(_app(card('thread-9-1-1.html', label: '我之前的拆机帖')));
    pending.values.single.completeError(StateError('无权限'));
    await tester.pumpAndSettle();
    expect(find.text('我之前的拆机帖'), findsOneWidget);
    expect(find.text('帖子'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('site-card-date-placeholder')),
      findsNothing,
    );
    await tester.tap(find.text('我之前的拆机帖'));
    await tester.pumpAndSettle();
    expect((opened.single.$1 as ThreadLink).tid, 9);
    expect(opened.single.$2, '我之前的拆机帖');
  });

  testWidgets('点击后用取到的标题打开', (tester) async {
    await tester.pumpWidget(_app(card('thread-2907156-1-1.html')));
    pending.values.single.complete(_archiver);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SiteLinkCard));
    await tester.pumpAndSettle();
    expect(opened.single.$2, '5080 公版拆机：均热板与供电布局细节');
  });

  testWidgets('文章卡片显示"文章"', (tester) async {
    await tester.pumpWidget(_app(card('article-50001-1.html')));
    await tester.pumpAndSettle();
    expect(find.text('文章'), findsOneWidget);
    expect(find.text('2026-09-30'), findsOneWidget);
  });

  testWidgets('320dp 宽加 2 倍字号不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(card('thread-2907156-1-1.html'), width: 320, textScale: 2),
    );
    pending.values.single.complete(_archiver);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('深色主题使用深色令牌', (tester) async {
    await tester.pumpWidget(
      _app(card('thread-2907156-1-1.html'), brightness: Brightness.dark),
    );
    pending.values.single.complete(_archiver);
    await tester.pumpAndSettle();
    final title = tester.widget<Text>(find.text('5080 公版拆机：均热板与供电布局细节'));
    expect(title.style!.color, AppTokens.dark.text);
  });

  testWidgets('卡片作为一个按钮朗读类型和标题', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(card('thread-2907156-1-1.html')));
    pending.values.single.complete(_archiver);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('帖子.*5080 公版拆机')), findsOneWidget);
    handle.dispose();
  });
}
