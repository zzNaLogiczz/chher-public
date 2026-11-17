import 'dart:async';
import 'dart:io';

import 'package:chh_app/data/forum_repository.dart';
import 'package:chh_app/data/portal_repository.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:chh_app/pages/thread_detail_page.dart';
import 'package:chh_app/parser/portal_parser.dart';
import 'package:chh_app/parser/thread_parser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Fetcher extends ChhFetcher {
  final urls = <Uri>[];
  final source = File('test_data/thread_synthetic.html').readAsStringSync();
  Completer<ChhResponse>? pending;
  @override
  String get name => 'local-portal-landing';
  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) async {
    urls.add(url);
    return pending?.future ?? ChhResponse(200, source);
  }
}

const _initial = ThreadDetail(
  tid: 900001,
  fid: 290,
  title: '本地落地首屏',
  posts: [
    Post(
      pid: 1,
      floor: 1,
      author: '本地作者',
      timeRaw: '',
      content: [TextBlock('已获取的落地首屏')],
    ),
  ],
  page: PageInfo(current: 1, hasNext: false),
);

void main() {
  test('portal dispatch preserves the already parsed thread page', () {
    final source = _Fetcher().source;
    final content = parsePortalContent(source, aid: 7) as ThreadContent;
    final direct = parseThread(source, tid: 900001);
    expect(content.detail!.tid, direct.tid);
    expect(
      content.detail!.posts.map((p) => p.pid),
      direct.posts.map((p) => p.pid),
    );
    expect(content.detail!.page.current, direct.page.current);
    expect(content.detail!.viewCount, direct.viewCount);
    expect(content.detail!.cookiePrefix, direct.cookiePrefix);
  });

  test(
    'in-flight portal landing keeps the generation it was requested under',
    () async {
      final fetcher = _Fetcher()..pending = Completer<ChhResponse>();
      final client = ChhClient(fetchers: [fetcher]);
      final previous = client.cacheGeneration;
      final request = PortalRepository(client).openArticle(7);
      await Future<void>.delayed(Duration.zero);
      client.clearCache();
      fetcher.pending!.complete(ChhResponse(200, fetcher.source));
      final content = await request as ThreadContent;
      expect(content.cacheGeneration, previous);
      expect(content.cacheGeneration, isNot(client.cacheGeneration));
    },
  );

  for (final mismatch in ['none', 'generation', 'unstamped', 'tid', 'page']) {
    testWidgets(
      'landing reuse requires matching session, tid and page: $mismatch',
      (tester) async {
        final fetcher = _Fetcher();
        final client = ChhClient(
          fetchers: [fetcher],
          threadRequestInterval: Duration.zero,
        );
        final generation = client.cacheGeneration;
        if (mismatch == 'generation') client.clearCache();
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(Brightness.light),
            home: ThreadDetailPage(
              tid: mismatch == 'tid' ? 900002 : 900001,
              title: '落地首屏',
              initialPage: mismatch == 'page' ? 2 : 1,
              initialDetail: _initial,
              initialDetailCacheGeneration: mismatch == 'unstamped'
                  ? null
                  : generation,
              repository: ForumRepository(client),
              preloadPages: 1,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(fetcher.urls.length, mismatch == 'none' ? 0 : 1);
        if (mismatch == 'none') {
          expect(find.text('已获取的落地首屏'), findsOneWidget);
          unawaited(
            tester
                .widget<RefreshIndicator>(find.byType(RefreshIndicator))
                .onRefresh(),
          );
          await tester.pumpAndSettle();
          expect(fetcher.urls, hasLength(1));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
