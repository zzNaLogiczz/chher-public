import 'package:chh_app/core/link_target.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/di.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:chh_app/pages/article_page.dart';
import 'package:chh_app/pages/thread_detail_page.dart';
import 'package:chh_app/widgets/article_discussion_widgets.dart';
import 'package:chh_app/widgets/post_card.dart';
import 'package:chh_app/widgets/site_link_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _PreviewFetcher extends ChhFetcher {
  final requested = <int>[];
  final unexpected = <Uri>[];
  int writes = 0;

  @override
  String get name => 'synthetic-link-group';

  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) async {
    final id = int.tryParse(
      RegExp(r'^/archiver/tid-(\d+)\.html$').firstMatch(url.path)?[1] ?? '',
    );
    if (id == null) {
      unexpected.add(url);
      return const ChhResponse(404, 'No synthetic route');
    }
    requested.add(id);
    return ChhResponse(200, '''<div id="content">
      <p class="author"><strong>合成作者$id</strong> 发表于 2026-11-15 10:00</p>
      <h3>合成链接$id</h3><p>合成摘要$id</p></div>''');
  }

  @override
  Future<ChhResponse> postForm(Uri url, Map<String, String> form) async {
    writes++;
    return const ChhResponse(403, 'Writes forbidden in this test');
  }
}

var _nextId = 980001;
List<SiteLinkBlock> _links([int count = 2]) => [
  for (var i = 0; i < count; i++)
    SiteLinkBlock(classifyLink('thread-${_nextId++}-1-1.html')!),
];

Post _post(List<ContentBlock> content, {bool opening = true}) => Post(
  pid: 1,
  floor: opening ? 1 : 2,
  author: '合成发帖者',
  timeRaw: '2026-11-15 10:00',
  content: content,
);

Future<void> _mount(
  WidgetTester tester,
  Widget child, {
  bool page = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      home: page ? child : Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectGroup(
  WidgetTester tester,
  List<SiteLinkBlock> links, {
  required bool compact,
}) {
  final group = tester.widget<SiteLinkGroupCard>(
    find.byType(SiteLinkGroupCard),
  );
  expect(group.blocks, links);
  expect(group.compact, compact);
  expect(
    find.byType(SiteLinkCard),
    findsNothing,
    reason: 'Adjacent links must not be wrapped as individual cards.',
  );
  for (final link in links) {
    final id = (link.target as ThreadLink).tid;
    expect(find.text('合成链接$id'), findsOneWidget);
    expect(
      find.text('合成摘要$id'),
      findsNothing,
      reason: 'Grouped links omit single-card summaries.',
    );
  }
  expect(tester.takeException(), isNull);
  expect(tester.binding.transientCallbackCount, 0);
}

void main() {
  late List<ChhFetcher> original;
  late _PreviewFetcher fake;
  setUp(() {
    original = List.of(chhClient.fetchers);
    fake = _PreviewFetcher();
    chhClient.fetchers
      ..clear()
      ..add(fake);
    chhClient.clearCache();
  });
  tearDown(() {
    chhClient.fetchers
      ..clear()
      ..addAll(original);
    chhClient.clearCache();
    expect(fake.unexpected, isEmpty);
    expect(fake.writes, 0);
  });

  for (final opening in [true, false]) {
    for (final lazy in [false, true]) {
      testWidgets(
        'PostCard ${lazy ? 'block' : 'whole'} ${opening ? 'opening' : 'reply'} renders one two-row card',
        (tester) async {
          final links = _links();
          final post = _post(links, opening: opening);
          await _mount(
            tester,
            lazy
                ? PostCard.block(
                    post: post,
                    isOpening: opening,
                    contentBlock: links.first,
                    siteLinks: links,
                  )
                : PostCard(post: post, isOpening: opening),
          );
          _expectGroup(tester, links, compact: !opening);
          expect(
            fake.requested,
            links.map((link) => (link.target as ThreadLink).tid),
          );
        },
      );
    }
  }

  testWidgets('article discussion groups consecutive links in compact card', (
    tester,
  ) async {
    final links = _links();
    await _mount(tester, DiscussionCommentContent(blocks: links));
    _expectGroup(tester, links, compact: true);
  });

  testWidgets('hidden discussion quotes remain a link-group boundary', (
    tester,
  ) async {
    final links = _links(4);
    await _mount(
      tester,
      DiscussionCommentContent(
        hideQuotes: true,
        blocks: [
          links[0],
          links[1],
          const QuoteBlock([TextBlock('合成历史引文')]),
          links[2],
          links[3],
        ],
      ),
    );
    expect(find.byType(DiscussionQuote), findsNothing);
    expect(find.text('合成历史引文'), findsNothing);
    final groups = tester
        .widgetList<SiteLinkGroupCard>(find.byType(SiteLinkGroupCard))
        .toList();
    expect(groups.map((group) => group.blocks), [
      links.take(2).toList(),
      links.skip(2).toList(),
    ]);
    expect(groups.every((group) => group.compact), isTrue);
    for (final link in links) {
      expect(
        find.text('合成链接${(link.target as ThreadLink).tid}'),
        findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('thread page passes adjacent links through lazy body segments', (
    tester,
  ) async {
    final links = _links();
    await _mount(
      tester,
      ThreadDetailPage(
        tid: 980000,
        title: '合成主题',
        loadPage: (_, _, _) async => ThreadDetail(
          tid: 980000,
          title: '合成主题',
          posts: [_post(links)],
          page: const PageInfo(current: 1, hasNext: false),
        ),
      ),
      page: true,
    );
    _expectGroup(tester, links, compact: false);
  });

  testWidgets('article page passes adjacent links through lazy body segments', (
    tester,
  ) async {
    final links = _links();
    await _mount(
      tester,
      ArticlePage(
        aid: 980000,
        title: '合成文章',
        loadPage: (_, _) async => ArticleContent(
          ArticleDetail(
            aid: 980000,
            title: '合成文章',
            content: links,
            page: const PageInfo(current: 1, hasNext: false),
          ),
        ),
      ),
      page: true,
    );
    _expectGroup(tester, links, compact: false);
  });

  for (final article in [false, true]) {
    testWidgets(
      '${article ? 'article' : 'thread'} lazily builds a thousand-link card by viewport',
      (tester) async {
        final links = _links(1000);
        await _mount(
          tester,
          article
              ? ArticlePage(
                  aid: 990000,
                  title: '合成长文章',
                  loadPage: (_, _) async => ArticleContent(
                    ArticleDetail(
                      aid: 990000,
                      title: '合成长文章',
                      content: links,
                      page: const PageInfo(current: 1, hasNext: false),
                    ),
                  ),
                )
              : ThreadDetailPage(
                  tid: 990000,
                  title: '合成长主题',
                  loadPage: (_, _, _) async => ThreadDetail(
                    tid: 990000,
                    title: '合成长主题',
                    posts: [_post(links)],
                    page: const PageInfo(current: 1, hasNext: false),
                  ),
                ),
          page: true,
        );
        final visible = tester
            .widgetList<SiteLinkGroupCard>(find.byType(SiteLinkGroupCard))
            .toList();
        expect(visible.length, inInclusiveRange(1, 20));
        expect(fake.requested.length, inInclusiveRange(1, 20));
        expect(
          visible.every((card) => card.grouped && card.blocks.length == 1),
          isTrue,
        );
        expect(visible.first.first, isTrue);
        expect(visible.any((card) => card.last), isFalse);
        expect(
          find.text('合成链接${(links.last.target as ThreadLink).tid}'),
          findsNothing,
        );
        expect(find.textContaining('合成摘要'), findsNothing);
        final initialRequests = fake.requested.length;
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
        await tester.pumpAndSettle();
        expect(fake.requested.length, greaterThan(initialRequests));
        expect(fake.requested.length, lessThanOrEqualTo(40));
        expect(tester.takeException(), isNull);
        expect(tester.binding.transientCallbackCount, 0);
      },
    );
  }
}
