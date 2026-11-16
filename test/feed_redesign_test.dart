import 'dart:async';
import 'dart:io';

import 'package:chh_app/data/forum_repository.dart';
import 'package:chh_app/data/editorial_cover_cache.dart';
import 'package:chh_app/data/portal_repository.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/pages/feed_page.dart';
import 'package:chh_app/ui/segmented.dart';
import 'package:chh_app/widgets/lacquer_tab_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Portal extends PortalRepository {
  _Portal() : super(ChhClient(fetchers: []));
  final opened = <int>[];
  @override
  Future<PortalHighlights> highlights({bool refresh = false}) async =>
      const PortalHighlights(
        reviews: [
          PortalArticle(
            aid: 234567,
            title: '样例评测',
            categoryName: '硬件',
            summary: '摘要',
          ),
        ],
        banners: [PortalArticle(aid: 234568, title: '样例社区精选')],
        news: [NewsItem(tid: 10, title: '样例快讯')],
      );
  @override
  Future<PortalContent> openArticle(
    int aid, {
    int page = 1,
    bool refresh = false,
    bool fallback = true,
  }) async {
    opened.add(aid);
    return ArticleContent(
      ArticleDetail(
        aid: aid,
        title: '无图样例',
        content: [],
        page: const PageInfo(current: 1, hasNext: false),
      ),
    );
  }
}

class _Forums extends ForumRepository {
  _Forums() : super(ChhClient(fetchers: []));
  final views = <String>[];
  Completer<ThreadListPage>? pending;
  ThreadListPage result(String view) => ThreadListPage(
    threads: List.generate(
      30,
      (i) => ThreadSummary(
        tid: 40000 + i,
        title: '$view 讨论 $i',
        author: '样例作者',
        replies: i,
        views: 0,
        forumName: '硬件讨论',
      ),
    ),
    page: const PageInfo(current: 1, hasNext: false),
  );
  @override
  Future<ThreadListPage> guide({
    String view = 'new',
    String? type,
    int page = 1,
    bool refresh = false,
  }) async {
    views.add(view);
    return pending?.future ?? Future.value(result(view));
  }
}

void main() {
  for (final style in AppearanceStyle.values) {
    for (final brightness in Brightness.values) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'feed ${style.name} ${brightness.name} scale $scale keeps data and toolbar sort in sync',
          (tester) async {
            tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            late Directory directory;
            late EditorialCoverCache covers;
            await tester.runAsync(() async {
              directory = await Directory.systemTemp.createTemp(
                'feed-widget-covers-',
              );
              covers = EditorialCoverCache.forTesting(
                File('${directory.path}/covers.json'),
              );
              await covers.load();
            });
            addTearDown(() async {
              covers.dispose();
              await directory.delete(recursive: true);
            });
            final portal = _Portal();
            final forums = _Forums();
            await tester.pumpWidget(
              MaterialApp(
                theme: buildAppTheme(brightness, style),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: FeedPage(
                  portalRepository: portal,
                  forumRepository: forums,
                  coverCache: covers,
                ),
              ),
            );
            await tester.pumpAndSettle();
            await tester.runAsync(() async {
              await covers.load();
            });
            await tester.pump();
            expect(portal.opened, [234567]);
            expect(find.text('灵感与日常'), findsNothing);
            final scaffold = tester.widget<LacquerTabScaffold>(
              find.byType(LacquerTabScaffold),
            );
            scaffold.controller!.jumpTo(1300);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            final visibleTitle = tester
                .widgetList<Text>(find.byType(Text))
                .map((t) => t.data)
                .whereType<String>()
                .firstWhere((text) => text.startsWith('new 讨论'));
            expect(find.text(visibleTitle), findsOneWidget);
            expect(tester.getTopLeft(find.text(visibleTitle)).dx, 34);
            forums.pending = Completer<ThreadListPage>();
            final controls = tester.widgetList<AppSegmented<String>>(
              find.byType(AppSegmented<String>),
            );
            controls.first.onChanged('hot');
            await tester.pump();
            expect(find.text(visibleTitle), findsOneWidget);
            expect(forums.views, ['new', 'hot']);
            expect(
              tester
                  .widgetList<AppSegmented<String>>(
                    find.byType(AppSegmented<String>),
                  )
                  .every((c) => c.value == 'hot'),
              isTrue,
            );
            forums.pending!.complete(forums.result('hot'));
            await tester.pumpAndSettle();
            expect(
              find.text(visibleTitle.replaceFirst('new', 'hot')),
              findsOneWidget,
            );
            expect(portal.opened, [234567]);
            await tester.pumpWidget(const SizedBox());
          },
        );
      }
    }
  }
}
