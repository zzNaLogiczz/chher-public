import 'dart:async';
import 'dart:io';

import 'package:chh_app/data/editorial_cover_cache.dart';
import 'package:chh_app/data/forum_repository.dart';
import 'package:chh_app/data/portal_repository.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/pages/feed_page.dart';
import 'package:chh_app/pages/forum_index_view.dart';
import 'package:chh_app/pages/medals_page.dart';
import 'package:chh_app/pages/messages_page.dart';
import 'package:chh_app/pages/user_page.dart';
import 'package:chh_app/ui/feedback.dart';
import 'package:chh_app/widgets/chhers_loader.dart';
import 'package:chh_app/widgets/chhers_refresh_indicator.dart';
import 'package:chh_app/widgets/expressive_controls.dart';
import 'package:chh_app/widgets/lacquer_tab_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'messages_ui_test.dart' show FakeMessages, notice, pmFixture;
import 'support/space_fixtures.dart';

PortalHighlights _highlights({String title = '初始精选', bool addReview = false}) =>
    PortalHighlights(
      reviews: [
        PortalArticle(aid: 400001, title: title),
        const PortalArticle(aid: 400002, title: '另一篇评测'),
        if (addReview) const PortalArticle(aid: 400005, title: '新加入的评测'),
      ],
      banners: const [PortalArticle(aid: 400003, title: '社区精选文章')],
      news: const [NewsItem(tid: 400004, title: '快讯标题')],
    );

class _Portal extends PortalRepository {
  _Portal() : super(ChhClient(fetchers: []));
  Completer<PortalHighlights>? pending;
  @override
  Future<PortalHighlights> highlights({bool refresh = false}) =>
      pending?.future ?? Future.value(_highlights());
  @override
  Future<PortalContent> openArticle(
    int aid, {
    int page = 1,
    bool refresh = false,
    bool fallback = true,
  }) async => ArticleContent(
    ArticleDetail(
      aid: aid,
      title: '离线无图样例',
      content: [],
      page: const PageInfo(current: 1, hasNext: false),
    ),
  );
}

class _Forum extends ForumRepository {
  _Forum() : super(ChhClient(fetchers: []));
  @override
  Future<ThreadListPage> guide({
    String view = 'new',
    String? type,
    int page = 1,
    bool refresh = false,
  }) async => const ThreadListPage(
    threads: [
      ThreadSummary(tid: 1, title: '讨论', author: '样例', replies: 0, views: 0),
    ],
    page: PageInfo(current: 1, hasNext: false),
  );
}

class _Space extends FixtureSpace {
  Completer<UserProfile>? pendingProfile;
  Completer<List<MedalItem>>? pendingMedals;
  @override
  Future<UserProfile> profile(String uid, {bool refresh = false}) =>
      pendingProfile?.future ?? super.profile(uid, refresh: refresh);
  @override
  Future<List<MedalItem>> medals({bool mine = false, bool refresh = false}) =>
      pendingMedals?.future ?? super.medals(mine: mine, refresh: refresh);
}

class _Messages extends FakeMessages {
  Completer<Paged<Notice>>? pendingNotices;
  Completer<Paged<PmConversation>>? pendingConversations;

  @override
  Future<Paged<PmConversation>> conversations({
    PmFilter filter = PmFilter.privatePm,
    int page = 1,
    bool refresh = false,
  }) =>
      pendingConversations?.future ??
      super.conversations(filter: filter, page: page, refresh: refresh);

  @override
  Future<Paged<Notice>> notices({
    NoticeView view = NoticeView.all,
    String? type,
    int page = 1,
    bool refresh = false,
  }) =>
      pendingNotices?.future ??
      super.notices(view: view, type: type, page: page, refresh: refresh);
}

Widget _app(
  Widget home, {
  AppearanceStyle style = AppearanceStyle.cinnabar,
  Brightness brightness = Brightness.light,
}) => MaterialApp(theme: buildAppTheme(brightness, style), home: home);

Future<void> _feed(
  WidgetTester tester,
  _Portal portal, {
  AppearanceStyle style = AppearanceStyle.cinnabar,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = const Size(390, 2100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  late Directory directory;
  late EditorialCoverCache covers;
  await tester.runAsync(() async {
    directory = await Directory.systemTemp.createTemp('refresh-covers-');
    covers = EditorialCoverCache.forTesting(
      File('${directory.path}/covers.json'),
    );
    await covers.load();
  });
  addTearDown(() async {
    covers.dispose();
    await directory.delete(recursive: true);
  });
  await tester.pumpWidget(
    _app(
      FeedPage(
        portalRepository: portal,
        forumRepository: _Forum(),
        coverCache: covers,
      ),
      style: style,
      brightness: brightness,
    ),
  );
}

Animation<double> _arrival(WidgetTester tester, int id) =>
    tester
            .widget<AnimatedBuilder>(
              find
                  .descendant(
                    of: find.byWidgetPredicate(
                      (widget) =>
                          widget is ExpressivePageReveal &&
                          widget.key is ValueKey &&
                          (widget.key as ValueKey).value == id,
                    ),
                    matching: find.byType(AnimatedBuilder),
                  )
                  .first,
            )
            .animation
        as Animation<double>;

Finder get _pullWordmark => find.byWidgetPredicate(
  (widget) => widget is ChhersLoader && widget.size == ChhersLoaderSize.refresh,
);

Future<TestGesture> _dragForWordmark(WidgetTester tester, Finder row) async {
  final gesture = await tester.startGesture(tester.getCenter(row));
  await gesture.moveBy(const Offset(0, 40));
  await tester.pump();
  final mark = tester.widget<ChhersLoader>(_pullWordmark);
  expect(mark.progress, inExclusiveRange(0, 1));
  final tokens = AppTokens.of(tester.element(_pullWordmark));
  final onLac = tokens.style == AppearanceStyle.cinnabar;
  expect(mark.color, onLac ? tokens.onLac : tokens.text3);
  await gesture.moveBy(const Offset(0, 260));
  await tester.pump();
  final armed = tester.widget<ChhersLoader>(_pullWordmark);
  expect(armed.progress, 1);
  expect(armed.color, onLac ? tokens.onLac : tokens.accent);
  return gesture;
}

void main() {
  for (final style in AppearanceStyle.values) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'feed refresh writes the wordmark and fades only new rows ${style.name} ${brightness.name}',
        (tester) async {
          final portal = _Portal();
          await _feed(tester, portal, style: style, brightness: brightness);
          await tester.pumpAndSettle();
          final oldFeatureState = tester.state(
            find.byKey(const ValueKey(400001)),
          );
          final oldMoreState = tester.state(find.byKey(const ValueKey(400002)));
          final oldSize = tester.getSize(find.byKey(const ValueKey(400001)));
          portal.pending = Completer<PortalHighlights>();
          final gesture = await _dragForWordmark(tester, find.text('初始精选'));
          await gesture.up();
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
          expect(tester.widget<ChhersLoader>(_pullWordmark).progress, isNull);
          for (final title in ['初始精选', '社区精选', '更多评测', '快讯', '快讯标题']) {
            expect(find.text(title), findsOneWidget);
          }
          expect(
            find.byKey(const ValueKey('feed-highlights-skeleton')),
            findsNothing,
          );
          expect(
            tester.state(find.byKey(const ValueKey(400001))),
            same(oldFeatureState),
          );
          expect(tester.getSize(find.byKey(const ValueKey(400001))), oldSize);
          expect(_arrival(tester, 400001).value, 1);
          portal.pending!.complete(
            _highlights(title: '更新后的精选', addReview: true),
          );
          await tester.pump();
          await tester.pump();
          expect(find.text('更新后的精选'), findsOneWidget);
          expect(
            tester.state(find.byKey(const ValueKey(400001))),
            same(oldFeatureState),
          );
          expect(
            tester.state(find.byKey(const ValueKey(400002))),
            same(oldMoreState),
          );
          expect(_arrival(tester, 400001).value, 1);
          expect(_arrival(tester, 400002).value, 1);
          expect(_arrival(tester, 1).value, 1);
          expect(_arrival(tester, 400005).value, 0);
          await tester.pump(const Duration(milliseconds: 90));
          expect(_arrival(tester, 400001).value, 1);
          expect(_arrival(tester, 400005).value, closeTo(.5, .01));
          expect(_arrival(tester, 400002).value, 1);
          await tester.pump(const Duration(milliseconds: 90));
          expect(_arrival(tester, 400001).value, 1);
          expect(_arrival(tester, 400005).value, 1);
          await tester.pump(const Duration(seconds: 2));
          expect(tester.binding.transientCallbackCount, 0);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets(
    'feed skeleton is first-load only and failed refresh preserves data',
    (tester) async {
      final portal = _Portal()..pending = Completer<PortalHighlights>();
      await _feed(tester, portal);
      expect(
        find.byKey(const ValueKey('feed-highlights-skeleton')),
        findsOneWidget,
      );
      portal.pending!.complete(_highlights());
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('feed-highlights-skeleton')),
        findsNothing,
      );
      portal.pending = Completer<PortalHighlights>();
      final refresh = tester
          .widget<LacquerTabScaffold>(find.byType(LacquerTabScaffold))
          .onRefresh!();
      final failed = expectLater(refresh, throwsStateError);
      await tester.pump();
      portal.pending!.completeError(StateError('offline'));
      await failed;
      await tester.pumpAndSettle();
      expect(find.text('初始精选'), findsOneWidget);
      expect(find.text('社区精选'), findsOneWidget);
      expect(find.text('未能刷新，轻点重试'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('feed-highlights-skeleton')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'profile refresh preserves identity and scroll widget while waiting',
    (tester) async {
      final repo = _Space();
      await tester.pumpWidget(_app(UserPage(uid: '42', repository: repo)));
      await tester.pumpAndSettle();
      final scroll = tester.element(find.byType(ListView));
      repo.pendingProfile = Completer<UserProfile>();
      final refresh = tester
          .widget<ChhersRefreshIndicator>(find.byType(ChhersRefreshIndicator))
          .onRefresh();
      await tester.pump();
      expect(find.byKey(UserPage.identityKey), findsOneWidget);
      expect(tester.element(find.byType(ListView)), same(scroll));
      repo.pendingProfile!.complete(const UserProfile(uid: '42', name: '新名字'));
      await refresh;
      await tester.pumpAndSettle();
      expect(find.text('新名字'), findsWidgets);
    },
  );

  testWidgets('profile identity change clears previous profile while waiting', (
    tester,
  ) async {
    final repo = _Space();
    Widget profile(String uid) => _app(
      Scaffold(
        body: UserProfileBody(uid: uid, repository: repo),
      ),
    );
    await tester.pumpWidget(profile('42'));
    await tester.pumpAndSettle();
    expect(find.byKey(UserPage.identityKey), findsOneWidget);
    repo.pendingProfile = Completer<UserProfile>();
    await tester.pumpWidget(profile('43'));
    expect(find.byKey(UserPage.identityKey), findsNothing);
    expect(find.text('装机爱好者'), findsNothing);
    expect(find.byType(ChhersLoader), findsOneWidget);
    repo.pendingProfile!.complete(const UserProfile(uid: '43', name: '另一位用户'));
    await tester.pumpAndSettle();
    expect(find.text('另一位用户'), findsOneWidget);
  });

  testWidgets('medal category change clears previous category while waiting', (
    tester,
  ) async {
    final repo = _Space();
    await tester.pumpWidget(_app(MedalsPage(repository: repo)));
    await tester.pumpAndSettle();
    expect(find.text('社区分享纪念勋章'), findsOneWidget);
    repo.pendingMedals = Completer<List<MedalItem>>();
    await tester.tap(find.text('我的勋章'));
    await tester.pump();
    expect(find.text('社区分享纪念勋章'), findsNothing);
    expect(find.byType(ChhersLoader), findsOneWidget);
    repo.pendingMedals!.complete(const [MedalItem(id: 'mine', name: '我的样例勋章')]);
    await tester.pumpAndSettle();
    expect(find.text('我的样例勋章'), findsOneWidget);
  });

  testWidgets('medals refresh retains rows until new data arrives', (
    tester,
  ) async {
    final repo = _Space();
    await tester.pumpWidget(_app(MedalsPage(repository: repo)));
    await tester.pumpAndSettle();
    repo.pendingMedals = Completer<List<MedalItem>>();
    final refresh = tester
        .widget<ChhersRefreshIndicator>(find.byType(ChhersRefreshIndicator))
        .onRefresh();
    await tester.pump();
    expect(find.text('社区分享纪念勋章'), findsOneWidget);
    repo.pendingMedals!.complete(const [MedalItem(id: 'new', name: '新勋章')]);
    await refresh;
    await tester.pumpAndSettle();
    expect(find.text('新勋章'), findsOneWidget);
  });

  for (final pm in [false, true]) {
    testWidgets(
      'messages refresh keeps ${pm ? 'PM rows' : 'notice rows'} opaque',
      (tester) async {
        final repo = _Messages();
        await tester.pumpWidget(
          _app(Scaffold(body: MessagesTabPage(repository: repo))),
        );
        await tester.pumpAndSettle();
        if (pm) {
          await tester.tap(find.text('私信').hitTestable().first);
          await tester.pumpAndSettle();
        }
        final row = find.ancestor(
          of: find.textContaining(pm ? '对方' : '坛友').hitTestable().first,
          matching: find.byType(ContentFade),
        );
        final element = tester.element(row);
        final origin = tester.getTopLeft(row);
        void expectRetained() {
          expect(tester.element(row), same(element));
          expect(tester.getTopLeft(row), origin);
          expect(tester.widget<ContentFade>(row).opacity.value, 1);
        }

        repo.pendingNotices = Completer<Paged<Notice>>();
        repo.pendingConversations = Completer<Paged<PmConversation>>();
        final refresh = tester
            .widget<LacquerTabScaffold>(find.byType(LacquerTabScaffold).first)
            .onRefresh!();
        await tester.pump();
        expectRetained();
        expect(find.byType(SkeletonPulse), findsNothing);
        if (pm) {
          repo.pendingConversations!.complete(
            const Paged(
              items: [pmFixture],
              page: PageInfo(current: 1, hasNext: false),
            ),
          );
        } else {
          repo.pendingNotices!.complete(
            const Paged(
              items: [notice],
              page: PageInfo(current: 1, hasNext: false),
            ),
          );
        }
        await refresh;
        await tester.pump();
        expectRetained();
        await tester.pump(const Duration(milliseconds: 90));
        expectRetained();
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets(
    'forum directory pull writes the wordmark and retains categories',
    (tester) async {
      final pending = Completer<List<ForumCategory>>();
      const categories = [
        ForumCategory(
          name: '互动区',
          forums: [Forum(fid: 1, name: '讨论区')],
        ),
      ];
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: ForumIndexView(
              loadForums: (refresh) =>
                  refresh ? pending.future : Future.value(categories),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final row = find.text('讨论区');
      final element = tester.element(row);
      final gesture = await _dragForWordmark(tester, row);
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.widget<ChhersLoader>(_pullWordmark).progress, isNull);
      expect(tester.element(row), same(element));
      pending.complete(categories);
      await tester.pump();
      expect(tester.element(row), same(element));
      await tester.pumpAndSettle();
      expect(_pullWordmark, findsNothing);
      expect(tester.element(row), same(element));
    },
  );
}
