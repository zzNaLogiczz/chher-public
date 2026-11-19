import 'dart:async';

import 'package:chh_app/core/display_time.dart';
import 'package:chh_app/core/link_target.dart';
import 'package:chh_app/data/link_preview_repository.dart';
import 'package:chh_app/design/motion.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/widgets/site_link_card.dart';
import 'package:chh_app/ui/feedback.dart';
import 'package:chh_app/design/link_card_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _archiver = '''
<div id="content"><p class="author"><strong>a</strong> 发表于 2026-10-19 14:41</p>
<h3>5080 公版拆机：均热板与供电布局细节</h3></div>''';

Widget _app(
  Widget child, {
  Brightness brightness = Brightness.light,
  double width = 390,
  double textScale = 1,
  AppearanceStyle style = AppearanceStyle.cinnabar,
}) => MaterialApp(
  theme: buildAppTheme(brightness, style),
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

  testWidgets('骨架到达后显示标题作者日期，不预留摘要空间', (tester) async {
    await tester.pumpWidget(
      _app(card('thread-2907156-1-1.html', label: '拆机帖')),
    );
    expect(find.text('拆机帖'), findsNothing);
    expect(find.text('帖子'), findsNothing);
    expect(
      find.byKey(const ValueKey('site-card-date-placeholder')),
      findsOneWidget,
    );

    pending.values.single.complete(_archiver);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(SiteLinkCard)).height, lessThan(100));
    expect(find.text('5080 公版拆机：均热板与供电布局细节'), findsOneWidget);
    expect(
      find.text(
        formatDisplayTime(
          at: DateTime(2026, 10, 19),
          style: DisplayTimeStyle.list,
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('a'), findsOneWidget);
    expect(find.text('拆机帖'), findsNothing);
  });

  testWidgets('链接文字就是网址时不暴露地址末段', (tester) async {
    await tester.pumpWidget(
      _app(card('https://www.chiphell.com/thread-2907156-1-1.html')),
    );
    expect(find.text('thread-2907156-1-1.html'), findsNothing);
    expect(find.text('站内帖子'), findsNothing);
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

  testWidgets('读取失败保留链接文字和打开入口', (tester) async {
    await tester.pumpWidget(_app(card('thread-9-1-1.html', label: '我之前的拆机帖')));
    pending.values.single.completeError(StateError('无权限'));
    await tester.pumpAndSettle();
    expect(find.text('我之前的拆机帖'), findsOneWidget);
    expect(find.text('帖子'), findsNothing);
    expect(
      find.byKey(const ValueKey('site-card-date-placeholder')),
      findsOneWidget,
    );
    expect(find.text('点开查看原帖'), findsNothing);
    await tester.tap(find.text('我之前的拆机帖'));
    await tester.pumpAndSettle();
    expect((opened.single.$1 as ThreadLink).tid, 9);
    expect(opened.single.$2, '我之前的拆机帖');
  });

  testWidgets('网址读取失败显示通用标题和查看原帖且可点', (tester) async {
    await tester.pumpWidget(
      _app(card('thread-9-1-1.html', label: 'chiphell.com/thread-9-1-1.html')),
    );
    final loadingSize = tester.getSize(find.byType(SiteLinkCard));
    pending.values.single.completeError(StateError('无权限'));
    await tester.pumpAndSettle();
    expect(find.text('站内帖子'), findsOneWidget);
    expect(find.text('点开查看原帖'), findsOneWidget);
    expect(find.text('chiphell.com/thread-9-1-1.html'), findsNothing);
    expect(tester.getSize(find.byType(SiteLinkCard)), loadingSize);
    await tester.tap(find.text('站内帖子'));
    await tester.pumpAndSettle();
    expect((opened.single.$1 as ThreadLink).tid, 9);
  });

  testWidgets('点击后用取到的标题打开', (tester) async {
    await tester.pumpWidget(_app(card('thread-2907156-1-1.html')));
    pending.values.single.complete(_archiver);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SiteLinkCard));
    await tester.pumpAndSettle();
    expect(opened.single.$2, '5080 公版拆机：均热板与供电布局细节');
  });

  testWidgets('文章显示标题日期且没有冗余类型', (tester) async {
    await tester.pumpWidget(_app(card('article-50001-1.html')));
    await tester.pumpAndSettle();
    expect(find.text('文章'), findsNothing);
    expect(
      find.text(
        formatDisplayTime(
          at: DateTime(2026, 9, 30),
          style: DisplayTimeStyle.list,
        ),
      ),
      findsOneWidget,
    );
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

  test('失败标题不显示网址或网址片段', () {
    for (final label in [
      '',
      'https://www.chiphell.com/thread-9-1-1.html',
      'thread-9-1-1.html',
      '/thread-9-1-1.html',
      'chiphell.com/thread-9-1-1.html',
      'chiphell.com/forum.php?mod=viewthread&tid=9',
    ]) {
      expect(
        siteLinkFallbackTitle(
          SiteLinkBlock(classifyLink('thread-9-1-1.html')!, label: label),
        ),
        '站内帖子',
      );
    }
    expect(
      siteLinkFallbackTitle(SiteLinkBlock(classifyLink('article-9-1.html')!)),
      '站内文章',
    );
    expect(
      siteLinkFallbackTitle(
        SiteLinkBlock(classifyLink('thread-9-1-1.html')!, label: '原始标题'),
      ),
      '原始标题',
    );
  });

  testWidgets('单张与分组都隐藏摘要且各行可打开', (tester) async {
    const content = _archiver;
    final withExcerpt = content.replaceFirst('</h3>', '</h3><p>合成摘要内容</p>');
    await tester.pumpWidget(_app(card('thread-1-1-1.html')));
    pending.values.single.complete(withExcerpt);
    await tester.pumpAndSettle();
    expect(find.text('合成摘要内容'), findsNothing);
    expect(tester.getSize(find.byType(SiteLinkCard)).height, lessThan(100));
    await tester.pumpWidget(
      _app(
        SiteLinkGroupCard(
          blocks: [
            SiteLinkBlock(classifyLink('thread-1-1-1.html')!),
            SiteLinkBlock(classifyLink('thread-2-1-1.html')!),
          ],
          repository: repo,
          onOpen: (target, title) => opened.add((target, title)),
        ),
      ),
    );
    pending.values.last.complete(withExcerpt);
    await tester.pumpAndSettle();
    expect(find.text('合成摘要内容'), findsNothing);
    await tester.tap(find.text('5080 公版拆机：均热板与供电布局细节').last);
    await tester.pumpAndSettle();
    expect((opened.single.$1 as ThreadLink).tid, 2);
    expect(tester.binding.transientCallbackCount, 0);
  });

  for (final compact in [false, true]) {
    testWidgets('短标题仅占一行，不为摘要撑高 compact=$compact', (tester) async {
      await tester.pumpWidget(
        _app(
          SiteLinkCard(
            block: SiteLinkBlock(classifyLink('thread-1-1-1.html')!),
            compact: compact,
            repository: repo,
          ),
        ),
      );
      pending.values.single.complete(
        _archiver
            .replaceFirst('5080 公版拆机：均热板与供电布局细节', '链接标题')
            .replaceFirst('</h3>', '</h3><p>不应显示的摘要</p>'),
      );
      await tester.pumpAndSettle();
      expect(find.text('不应显示的摘要'), findsNothing);
      expect(
        tester.getSize(find.byType(SiteLinkCard)).height,
        lessThan(compact ? 70 : 80),
      );
      expect(
        tester.getTopLeft(find.text('a')).dy -
            tester.getBottomLeft(find.text('链接标题')).dy,
        closeTo(4, 1),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('整组骨架首帧可见，内容到达后停止呼吸', (tester) async {
    await tester.pumpWidget(
      _app(
        SiteLinkGroupCard(
          blocks: [
            SiteLinkBlock(classifyLink('thread-1-1-1.html')!),
            SiteLinkBlock(classifyLink('thread-2-1-1.html')!),
          ],
          repository: repo,
        ),
      ),
    );
    expect(find.byType(SkeletonPulse), findsOneWidget);
    expect(find.byType(LoadingPlaceholder), findsNothing);
    expect(
      find.byKey(const ValueKey('site-card-title-placeholder-0')),
      findsNWidgets(2),
    );
    double opacity() => tester
        .widget<Opacity>(
          find
              .descendant(
                of: find.byType(SkeletonPulse),
                matching: find.byType(Opacity),
              )
              .first,
        )
        .opacity;
    expect(opacity(), 1);
    await tester.pump();
    await tester.pump(AppMotion.skeletonCycle ~/ 2);
    expect(opacity(), lessThan(1));
    for (final request in pending.values) {
      request.complete(_archiver);
    }
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('双行链接骨架与标题同高，文字到达时交叉淡入', (tester) async {
    const title = '宽屏显示器横向评测与不同环境的色彩对比测试结果汇总';
    await tester.pumpWidget(
      _app(card('thread-2907156-1-1.html', label: title)),
    );
    final cardFinder = find.byType(SiteLinkCard);
    final firstBar = find.byKey(
      const ValueKey('site-card-title-placeholder-0'),
    );
    final secondBar = find.byKey(
      const ValueKey('site-card-title-placeholder-1'),
    );
    final dateBar = find.byKey(const ValueKey('site-card-date-placeholder'));
    final height = tester.getSize(cardFinder);
    final firstBarY = tester.getCenter(firstBar).dy;
    final secondBarY = tester.getCenter(secondBar).dy;
    final dateY = tester.getCenter(dateBar).dy;
    expect(find.text(title), findsNothing);

    pending.values.single.complete(
      _archiver.replaceFirst('5080 公版拆机：均热板与供电布局细节', title),
    );
    await tester.pump();
    await tester.pump();
    final textFinder = find.text(title);
    final textFade = find.ancestor(
      of: textFinder,
      matching: find.byType(AnimatedOpacity),
    );
    final skeletonFade = find.ancestor(
      of: dateBar,
      matching: find.byType(AnimatedOpacity),
    );
    double opacity(Finder finder) =>
        tester.renderObject<RenderAnimatedOpacity>(finder.first).opacity.value;
    expect(tester.getSize(cardFinder), height);
    expect(opacity(textFade), 0);
    expect(opacity(skeletonFade), 1);
    await tester.pump(AppMotion.fade ~/ 2);
    expect(opacity(textFade), closeTo(.5, .01));
    expect(opacity(skeletonFade), closeTo(.5, .01));
    await tester.pumpAndSettle();
    expect(opacity(textFade), 1);
    expect(opacity(skeletonFade), 0);
    expect(tester.getSize(cardFinder), height);
    expect(tester.getTopLeft(textFinder).dy, lessThan(firstBarY));
    expect(tester.getBottomLeft(textFinder).dy, greaterThan(secondBarY));
    expect(tester.getTopLeft(find.text('a')).dy, lessThan(dateY));
    expect(tester.getBottomLeft(find.text('a')).dy, greaterThan(dateY));
  });

  for (final style in AppearanceStyle.values) {
    for (final brightness in Brightness.values) {
      testWidgets('纯图单卡 ${style.name} ${brightness.name} 无摘要高度且缓存与打开正常', (
        tester,
      ) async {
        const imageUrl = 'https://static.chiphell.com/forum/synthetic.jpg';
        final imageOnly = _archiver.replaceFirst(
          '</h3>',
          '</h3><p>$imageUrl</p><p><img src="$imageUrl" alt="合成图片"></p>',
        );
        final target = classifyLink('thread-1-1-1.html')!;
        await tester.pumpWidget(
          _app(card('thread-1-1-1.html'), style: style, brightness: brightness),
        );
        pending.values.single.complete(imageOnly);
        await tester.pumpAndSettle();
        final readySize = tester.getSize(find.byType(SiteLinkCard));
        expect(readySize.height, lessThan(100));
        expect(repo.cached(target)!.excerpt, isNull);
        expect(find.text(imageUrl), findsNothing);
        expect(find.text('合成图片'), findsNothing);
        expect(find.text('5080 公版拆机：均热板与供电布局细节'), findsOneWidget);
        expect(find.text('a'), findsOneWidget);
        expect(
          find.text(
            formatDisplayTime(
              at: DateTime(2026, 10, 19),
              style: DisplayTimeStyle.list,
            ),
          ),
          findsOneWidget,
        );
        expect(tester.binding.transientCallbackCount, 0);

        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          _app(card('thread-1-1-1.html'), style: style, brightness: brightness),
        );
        expect(tester.getSize(find.byType(SiteLinkCard)), readySize);
        expect(pending, hasLength(1));
        await tester.tap(find.byType(SiteLinkCard));
        await tester.pumpAndSettle();
        expect((opened.single.$1 as ThreadLink).tid, 1);
        expect(opened.single.$2, '5080 公版拆机：均热板与供电布局细节');
        expect(tester.takeException(), isNull);
      });

      testWidgets('紧凑卡 ${style.name} ${brightness.name} 使用主题令牌且没有阴影', (
        tester,
      ) async {
        await tester.pumpWidget(
          _app(
            SiteLinkCard(
              block: SiteLinkBlock(classifyLink('thread-1-1-1.html')!),
              compact: true,
              repository: repo,
            ),
            style: style,
            brightness: brightness,
          ),
        );
        pending.values.single.complete(_archiver);
        await tester.pumpAndSettle();
        final title = tester.widget<Text>(find.text('5080 公版拆机：均热板与供电布局细节'));
        expect(title.style!.fontSize, LinkCardTokens.compactTitle.fontSize);
        expect(title.style!.color, tokensFor(brightness, style).text);
        final box = tester.widget<DecoratedBox>(
          find
              .descendant(
                of: find.byType(SiteLinkGroupCard),
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        expect((box.decoration as BoxDecoration).boxShadow, isNull);
        expect(
          (box.decoration as BoxDecoration).color,
          tokensFor(brightness, style).fill,
        );
      });
    }
  }

  for (final compact in [false, true]) {
    testWidgets('逐行切片保持整组高度和首尾圆角 compact=$compact', (tester) async {
      final blocks = [
        SiteLinkBlock(classifyLink('thread-1-1-1.html')!),
        SiteLinkBlock(classifyLink('thread-2-1-1.html')!),
      ];
      await tester.pumpWidget(
        _app(
          SiteLinkGroupCard(blocks: blocks, compact: compact, repository: repo),
        ),
      );
      for (final request in pending.values) {
        request.complete(
          _archiver.replaceFirst('</h3>', '</h3><p>摘要不应出现在组内</p>'),
        );
      }
      await tester.pumpAndSettle();
      final height = tester.getSize(find.byType(SiteLinkGroupCard)).height;
      await tester.pumpWidget(
        _app(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SiteLinkGroupCard(
                key: const ValueKey('first-slice'),
                blocks: [blocks[0]],
                compact: compact,
                grouped: true,
                last: false,
                repository: repo,
              ),
              SiteLinkGroupCard(
                key: const ValueKey('last-slice'),
                blocks: [blocks[1]],
                compact: compact,
                grouped: true,
                first: false,
                repository: repo,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final first = find.byKey(const ValueKey('first-slice'));
      final last = find.byKey(const ValueKey('last-slice'));
      expect(
        tester.getSize(first).height + tester.getSize(last).height,
        closeTo(height, .001),
      );
      expect(find.text('摘要不应出现在组内'), findsNothing);
      BoxDecoration decoration(Finder slice) =>
          tester
                  .widget<DecoratedBox>(
                    find
                        .descendant(
                          of: slice,
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      final firstRadius = decoration(first).borderRadius! as BorderRadius;
      final lastRadius = decoration(last).borderRadius! as BorderRadius;
      expect(
        firstRadius.topLeft.x,
        compact ? LinkCardTokens.compactRadius : LinkCardTokens.radius,
      );
      expect(firstRadius.bottomLeft, Radius.zero);
      expect(lastRadius.topLeft, Radius.zero);
      expect(lastRadius.bottomLeft, firstRadius.topLeft);
      if (!compact) {
        final firstClip = tester.widget<ClipRect>(
          find.descendant(of: first, matching: find.byType(ClipRect)).first,
        );
        final lastClip = tester.widget<ClipRect>(
          find.descendant(of: last, matching: find.byType(ClipRect)).first,
        );
        final firstBounds = firstClip.clipper!.getClip(tester.getSize(first));
        final lastBounds = lastClip.clipper!.getClip(tester.getSize(last));
        expect(firstBounds.top, lessThan(0));
        expect(firstBounds.bottom, tester.getSize(first).height);
        expect(lastBounds.top, 0);
        expect(lastBounds.bottom, greaterThan(tester.getSize(last).height));
      }
    });
  }

  testWidgets('重复网址保留两行且只请求一次', (tester) async {
    final target = classifyLink('thread-1-1-1.html')!;
    await tester.pumpWidget(
      _app(
        SiteLinkGroupCard(
          blocks: [SiteLinkBlock(target), SiteLinkBlock(target)],
          repository: repo,
          onOpen: (target, title) => opened.add((target, title)),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(pending, hasLength(1));
    pending.values.single.complete(_archiver);
    await tester.pumpAndSettle();
    expect(find.text('5080 公版拆机：均热板与供电布局细节'), findsNWidgets(2));
    await tester.tap(find.text('5080 公版拆机：均热板与供电布局细节').last);
    await tester.pumpAndSettle();
    expect(opened.single.$1, target);
  });

  testWidgets('长组切片随Sliver惰性创建且不提前请求屏外行', (tester) async {
    var fetched = 0;
    final lazyRepo = LinkPreviewRepository(
      fetchHtml: (_) async {
        fetched++;
        return _archiver;
      },
      openArticle: (_) async => throw UnimplementedError(),
    );
    await tester.pumpWidget(
      _app(
        SizedBox(
          height: 200,
          child: ListView.builder(
            scrollCacheExtent: const ScrollCacheExtent.pixels(0),
            itemCount: 40,
            itemBuilder: (_, index) => SiteLinkGroupCard(
              blocks: [
                SiteLinkBlock(classifyLink('thread-${index + 1}-1-1.html')!),
              ],
              grouped: true,
              first: index == 0,
              last: index == 39,
              repository: lazyRepo,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final initial = fetched;
    expect(initial, greaterThan(0));
    expect(initial, lessThan(10));
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(fetched, greaterThan(initial));
    expect(fetched, lessThan(40));
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
