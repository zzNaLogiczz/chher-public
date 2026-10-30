/// 收藏交互只用内存索引与本地仓库,不访问论坛。
library;

import 'dart:async';

import 'package:chh_app/data/favorite_repository.dart';
import 'package:chh_app/data/forum_repository.dart';
import 'package:chh_app/data/space_repository.dart';
import 'package:chh_app/design/icons.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/di.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/pages/forum_index_view.dart';
import 'package:chh_app/pages/forum_threads_page.dart';
import 'package:chh_app/pages/favorites_page.dart';
import 'package:chh_app/ui/chrome_button.dart';
import 'package:chh_app/ui/favorite_action.dart';
import 'package:chh_app/ui/reading_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _target = FavoriteTarget(
  type: FavoriteType.thread,
  targetId: 42,
  title: '本地帖子',
);
const _forum = FavoriteItem(
  type: FavoriteType.forum,
  targetId: 80,
  favid: '201',
  title: '收藏摄影版块',
  url: 'forum-80-1.html',
);
const _forum2 = FavoriteItem(
  type: FavoriteType.forum,
  targetId: 81,
  favid: '202',
  title: '收藏电脑版块',
  url: 'forum-81-1.html',
);

class _Favorites extends FavoriteRepository {
  final FavoriteIndex localIndex;
  Completer<void>? pending;
  bool fail = false;
  int calls = 0;
  _Favorites(this.localIndex) : super(ChhClient(fetchers: []), localIndex);

  @override
  Future<FavoriteToggle> add(FavoriteTarget target) async {
    calls++;
    await pending?.future;
    if (fail) throw StateError('本地失败');
    localIndex.put(target, favid: '300');
    return const FavoriteToggle(true);
  }

  @override
  Future<FavoriteToggle> remove(FavoriteTarget target) async {
    calls++;
    await pending?.future;
    if (fail) throw StateError('本地失败');
    localIndex.remove(target);
    return const FavoriteToggle(false);
  }
}

class _Space extends SpaceRepository {
  _Space() : super(ChhClient(fetchers: []));
  Completer<Paged<FavoriteItem>>? pending;
  @override
  Future<Paged<FavoriteItem>> favorites({
    FavoriteType type = FavoriteType.all,
    int page = 1,
    bool refresh = false,
  }) async => pending != null
      ? await pending!.future
      : Paged(
          items: [
            for (var i = 0; i < 20; i++)
              FavoriteItem(
                type: FavoriteType.forum,
                targetId: page * 100 + i,
                favid: '${page * 100 + i}',
                title: '收藏版块 $page-$i',
                url: 'forum-${page * 100 + i}-1.html',
              ),
          ],
          page: PageInfo(current: page, hasNext: page == 1),
        );
}

class _Forums extends ForumRepository {
  _Forums() : super(ChhClient(fetchers: []));
  @override
  Future<List<ThreadType>> threadTypes(int fid, {bool refresh = false}) async =>
      [];
  @override
  Future<ThreadListPage> threadList(
    int fid, {
    int page = 1,
    int? typeid,
    String? filter,
    String? orderby,
    bool refresh = false,
  }) async => const ThreadListPage(
    threads: [],
    page: PageInfo(current: 1, hasNext: false),
  );
}

Widget _app(Widget child, {Map<String, WidgetBuilder>? routes}) => MaterialApp(
  theme: buildAppTheme(Brightness.light),
  routes: routes ?? const {},
  home: Scaffold(body: child),
);

Widget _action(
  FavoriteIndex index,
  _Favorites repository, {
  bool loggedIn = true,
}) => _app(
  FavoriteActionBuilder(
    target: _target,
    index: index,
    repository: repository,
    isLoggedIn: () => loggedIn,
    builder: (context, favorited, busy, toggle) => ReadingBar(
      placeholder: '写回复…',
      onCompose: () {},
      inComments: false,
      onShowComments: () {},
      onBackToTop: () {},
      favorited: favorited,
      favoriteBusy: busy,
      onToggleFavorite: toggle,
    ),
  ),
);

void main() {
  setUp(() {
    chhSession.loggedIn = false;
    favoriteIndex.setUid(null);
  });
  tearDown(() {
    chhSession.loggedIn = false;
    favoriteIndex.setUid(null);
  });

  testWidgets(
    'favorite changes optimistically, prevents repeats and reports success',
    (tester) async {
      final index = FavoriteIndex(null)..setUid(1);
      final repository = _Favorites(index)..pending = Completer<void>();
      await tester.pumpWidget(_action(index, repository));
      await tester.tap(find.byKey(ReadingBar.favoriteKey));
      await tester.pump();
      expect(find.byTooltip('取消收藏'), findsOneWidget);
      expect(index.contains(_target), isFalse);
      expect(
        tester.widget<ReadingBar>(find.byType(ReadingBar)).favoriteBusy,
        isTrue,
      );
      await tester.tap(find.byKey(ReadingBar.favoriteKey));
      expect(repository.calls, 1);
      repository.pending!.complete();
      await tester.pump();
      expect(index.contains(_target), isTrue);
      expect(find.text('已收藏'), findsOneWidget);
      await tester.pumpAndSettle();
      repository.pending = null;
      await tester.tap(find.byKey(ReadingBar.favoriteKey));
      await tester.pump();
      expect(index.contains(_target), isFalse);
      expect(find.byTooltip('收藏'), findsOneWidget);
      expect(find.text('已取消收藏'), findsOneWidget);
      await tester.pumpAndSettle();
      index.dispose();
    },
  );

  testWidgets('add and remove failures restore their previous state', (
    tester,
  ) async {
    final index = FavoriteIndex(null)..setUid(1);
    final repository = _Favorites(index)..fail = true;
    await tester.pumpWidget(_action(index, repository));
    await tester.tap(find.byKey(ReadingBar.favoriteKey));
    await tester.pump();
    expect(find.byTooltip('收藏'), findsOneWidget);
    expect(find.text('收藏未完成，请重试'), findsOneWidget);
    expect(index.contains(_target), isFalse);
    await tester.pumpAndSettle();
    index.put(_target, favid: '300');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ReadingBar.favoriteKey));
    await tester.pump();
    expect(find.byTooltip('取消收藏'), findsOneWidget);
    expect(find.text('取消未完成，请重试'), findsOneWidget);
    expect(index.contains(_target), isTrue);
    await tester.pumpAndSettle();
    index.dispose();
  });

  testWidgets('guest favorite opens login without submitting', (tester) async {
    final index = FavoriteIndex(null);
    final repository = _Favorites(index);
    await tester.pumpWidget(
      _app(
        FavoriteActionBuilder(
          target: _target,
          index: index,
          repository: repository,
          isLoggedIn: () => false,
          builder: (_, favorited, busy, toggle) => ReadingBar(
            placeholder: '写回复…',
            onCompose: () {},
            inComments: false,
            onShowComments: () {},
            onBackToTop: () {},
            favorited: favorited,
            favoriteBusy: busy,
            onToggleFavorite: toggle,
          ),
        ),
        routes: {'/login': (_) => const Scaffold(body: Text('本地登录页'))},
      ),
    );
    await tester.tap(find.byKey(ReadingBar.favoriteKey));
    await tester.pumpAndSettle();
    expect(find.text('本地登录页'), findsOneWidget);
    expect(repository.calls, 0);
    index.dispose();
  });

  testWidgets(
    'forum favorite uses selected bold bookmark and updates from index',
    (tester) async {
      chhSession.loggedIn = true;
      favoriteIndex.setUid(1);
      await tester.pumpWidget(
        _app(ForumThreadsPage(fid: 80, title: '摄影', repository: _Forums())),
      );
      await tester.pumpAndSettle();
      ChromeGroupItem action() =>
          tester.widget<ChromeGroup>(find.byType(ChromeGroup)).items.last;
      expect(action().selected, isFalse);
      expect(action().icon, AppIcons.bookmark);
      favoriteIndex.merge([_forum]);
      await tester.pump();
      expect(action().selected, isTrue);
      expect(action().icon, AppIcons.bookmarkFilled);
      expect(action().tooltip, '取消收藏版块');
    },
  );

  testWidgets(
    'directory favorites lead categories, preserve order and respect search and category',
    (tester) async {
      chhSession.loggedIn = true;
      favoriteIndex.setUid(1);
      favoriteIndex.merge([
        _forum,
        _forum2,
        const FavoriteItem(
          type: FavoriteType.thread,
          targetId: 42,
          favid: '300',
          title: '帖子不显示',
          url: 'thread-42-1-1.html',
        ),
      ]);
      await tester.pumpWidget(
        _app(
          ForumIndexView(
            loadForums: (_) async => const [
              ForumCategory(
                name: '硬件',
                forums: [Forum(fid: 1, name: '普通电脑')],
              ),
              ForumCategory(
                name: '生活',
                forums: [Forum(fid: 2, name: '普通摄影')],
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('收藏'), findsOneWidget);
      expect(find.text('帖子不显示'), findsNothing);
      expect(
        tester.getTopLeft(find.text('收藏')).dy,
        lessThan(tester.getTopLeft(find.text('硬件')).dy),
      );
      expect(
        tester.getTopLeft(find.text('收藏摄影版块')).dy,
        lessThan(tester.getTopLeft(find.text('收藏电脑版块')).dy),
      );
      await tester.enterText(find.byType(EditableText), '摄影');
      await tester.pumpAndSettle();
      expect(find.text('收藏摄影版块'), findsOneWidget);
      expect(find.text('收藏电脑版块'), findsNothing);
      await tester.enterText(find.byType(EditableText), '不匹配');
      await tester.pumpAndSettle();
      expect(find.text('收藏'), findsNothing);
      await tester.tap(find.byTooltip('清除搜索'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全部分区'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('硬件').last);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      expect(find.text('收藏'), findsNothing);
      expect(find.text('收藏摄影版块'), findsNothing);
      expect(find.text('普通电脑'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('directory hides empty and guest favorites', (tester) async {
    chhSession.loggedIn = true;
    favoriteIndex.setUid(1);
    Widget directory() => _app(
      ForumIndexView(
        loadForums: (_) async => const [
          ForumCategory(
            name: '硬件',
            forums: [Forum(fid: 1, name: '普通电脑')],
          ),
        ],
      ),
    );
    await tester.pumpWidget(directory());
    await tester.pumpAndSettle();
    expect(find.text('收藏'), findsNothing);
    favoriteIndex.merge([_forum]);
    await tester.pumpAndSettle();
    expect(find.text('收藏'), findsOneWidget);
    chhSession.loggedIn = false;
    favoriteIndex.setUid(null);
    await tester.pumpAndSettle();
    expect(find.text('收藏'), findsNothing);
  });
  testWidgets(
    'each loaded favorite page merges without removing earlier entries',
    (tester) async {
      chhSession.loggedIn = true;
      favoriteIndex.setUid(1);
      favoriteIndex.merge([_forum]);
      await tester.pumpWidget(_app(FavoritesBody(repository: _Space())));
      await tester.pumpAndSettle();
      expect(favoriteIndex.items.any((item) => item.targetId == 100), isTrue);
      expect(favoriteIndex.items.any((item) => item.targetId == 80), isTrue);
      for (
        var i = 0;
        i < 8 && !favoriteIndex.items.any((item) => item.targetId == 200);
        i++
      ) {
        await tester.drag(find.byType(ListView), const Offset(0, -700));
        await tester.pumpAndSettle();
      }
      expect(favoriteIndex.items.any((item) => item.targetId == 200), isTrue);
      expect(favoriteIndex.items.any((item) => item.targetId == 100), isTrue);
      expect(favoriteIndex.items.any((item) => item.targetId == 80), isTrue);
    },
  );
  testWidgets(
    'favorite page ignores an old response after the same account logs in again',
    (tester) async {
      chhSession.loggedIn = true;
      favoriteIndex.setUid(1);
      final repository = _Space()..pending = Completer<Paged<FavoriteItem>>();
      await tester.pumpWidget(_app(FavoritesBody(repository: repository)));
      await tester.pump();
      favoriteIndex.setUid(null);
      favoriteIndex.setUid(1);
      repository.pending!.complete(
        const Paged(
          items: [_forum],
          page: PageInfo(current: 1, hasNext: false),
        ),
      );
      await tester.pumpAndSettle();
      expect(favoriteIndex.items, isEmpty);
    },
  );
}
