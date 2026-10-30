import 'package:chh_app/design/theme.dart';
import 'package:chh_app/di.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:chh_app/pages/my_threads_page.dart';
import 'package:chh_app/pages/thread_detail_page.dart';
import 'package:chh_app/pages/user_drawer.dart';
import 'package:chh_app/pages/user_page.dart';
import 'package:chh_app/ui/chrome_button.dart';
import 'package:chh_app/ui/press.dart';
import 'package:chh_app/widgets/post_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/space_fixtures.dart';

const _locked = Post(
  pid: 10,
  floor: 1,
  author: '用户',
  timeRaw: '10:00',
  content: [],
  lock: PostLock(text: '本帖为密码帖，请输入密码', needsPassword: true),
);

void main() {
  testWidgets('锁定楼层保留作者和回复入口，密码操作可用', (tester) async {
    var unlocks = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: PostCard(
            post: _locked,
            isOpening: true,
            onUnlock: () => unlocks++,
            onReply: () {},
          ),
        ),
      ),
    );
    expect(find.text('用户'), findsOneWidget);
    expect(find.text('本帖为密码帖，请输入密码'), findsOneWidget);
    expect(find.text('回复'), findsOneWidget);
    await tester.tap(find.text('输入密码'));
    expect(unlocks, 1);
    final avatar = tester.widget<PressScale>(
      find.byKey(const ValueKey('post-profile-10')),
    );
    expect(avatar.onTap, isNull);
  });

  testWidgets('屏蔽提示与惰性首楼只展示一次，不出现密码操作', (tester) async {
    const post = Post(
      pid: 11,
      floor: 1,
      author: '用户',
      timeRaw: '',
      content: [],
      lock: PostLock(text: '作者被禁止或删除 内容自动屏蔽', needsPassword: false),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: const Scaffold(
          body: Column(
            children: [
              PostCard.header(post: post, isOpening: true),
              PostCard.footer(post: post, isOpening: true),
            ],
          ),
        ),
      ),
    );
    expect(find.text('作者被禁止或删除 内容自动屏蔽'), findsOneWidget);
    expect(find.text('输入密码'), findsNothing);
  });

  testWidgets('评论视图保留正文内的站点锁提示', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: const Scaffold(
          body: PostCard(
            post: Post(
              pid: 12,
              floor: 2,
              author: '用户',
              timeRaw: '',
              content: [
                QuoteBlock([TextBlock('需要更高积分')], isNotice: true),
              ],
            ),
            isOpening: false,
            commentStyle: true,
          ),
        ),
      ),
    );
    expect(find.text('需要更高积分'), findsOneWidget);
  });

  for (final target in ['avatar', 'author']) {
    testWidgets('点击$target打开用户抽屉，关闭保留帖子位置且不重读', (tester) async {
      final originalFetchers = List<ChhFetcher>.of(chhClient.fetchers);
      chhClient.fetchers
        ..clear()
        ..add(_ProfileFetcher());
      chhClient.clearCache();
      addTearDown(() {
        chhClient.fetchers
          ..clear()
          ..addAll(originalFetchers);
        chhClient.clearCache();
      });
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: ThreadDetailPage(
            tid: 123,
            title: '抽屉阅读测试',
            loadPage: (_, _, _) async {
              calls++;
              return ThreadDetail(
                tid: 123,
                title: '抽屉阅读测试',
                posts: [
                  for (var i = 1; i <= 20; i++)
                    Post(
                      pid: i,
                      floor: i,
                      author: '作者$i',
                      authorUid: '$i',
                      timeRaw: '10:00',
                      content: [TextBlock('第$i楼正文')],
                    ),
                ],
                page: const PageInfo(current: 1, hasNext: false),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final entry = find.byKey(ValueKey('post-$target-4'));
      await tester.scrollUntilVisible(
        entry,
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(tester.element(entry), alignment: .4);
      await tester.pumpAndSettle();
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      final before = position.pixels;
      expect(before, greaterThan(0));
      final size = tester.getSize(entry);
      if (target == 'avatar') {
        expect(size, const Size(38, 28));
      } else {
        expect(size, tester.getSize(find.text('作者4')));
      }
      expect(tester.widget<PressScale>(entry).semanticLabel, '查看作者4的主页');
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.byType(UserDrawer), findsOneWidget);
      expect(find.byType(UserProfileBody), findsOneWidget);
      expect(find.text('离线用户主页'), findsNWidgets(2));
      final route = ModalRoute.of(tester.element(find.byType(UserDrawer)))!;
      expect(route.opaque, isFalse);
      await tester.tap(
        find.byWidgetPredicate((w) => w is ChromeButton && w.tooltip == '关闭'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(UserDrawer), findsNothing);
      expect(position.pixels, before);
      expect(calls, 1);
      expect(tester.takeException(), isNull);
    });
  }

  for (final commentStyle in [false, true]) {
    testWidgets('${commentStyle ? '评论' : '整楼'}样式的主页入口不改变楼层高度', (tester) async {
      Post post(String? uid) => Post(
        pid: 4,
        floor: 4,
        author: '作者4',
        authorUid: uid,
        timeRaw: '10:00',
        content: const [TextBlock('正文内容')],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  for (final uid in <String?>['4', null])
                    PostCard(
                      key: ValueKey(uid ?? 'anonymous'),
                      post: post(uid),
                      isOpening: false,
                      commentStyle: commentStyle,
                      isAuthor: true,
                      onReply: () {},
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      final linked = find.byKey(const ValueKey('4'));
      final anonymous = find.byKey(const ValueKey('anonymous'));
      expect(tester.getSize(linked).height, tester.getSize(anonymous).height);
      final profileLink = find.byWidgetPredicate(
        (widget) => widget is PressScale && widget.semanticLabel == '查看作者4的主页',
      );
      final links = find.descendant(of: linked, matching: profileLink);
      final disabledLinks = find.descendant(
        of: anonymous,
        matching: profileLink,
      );
      expect(links, findsNWidgets(commentStyle ? 2 : 1));
      for (final entry in links.evaluate()) {
        expect((entry.widget as PressScale).onTap, isNotNull);
        expect((entry.widget as PressScale).semanticLabel, '查看作者4的主页');
      }
      for (final entry in disabledLinks.evaluate()) {
        expect((entry.widget as PressScale).onTap, isNull);
      }
      final name = find.descendant(of: linked, matching: find.text('作者4'));
      final time = find.descendant(of: linked, matching: find.text('10:00'));
      final badge = find.descendant(of: linked, matching: find.text('楼主'));
      final body = find.descendant(of: linked, matching: find.text('正文内容'));
      expect(find.ancestor(of: name, matching: links), findsOneWidget);
      expect(
        find.ancestor(of: time, matching: links),
        commentStyle ? findsNothing : findsOneWidget,
      );
      expect(
        find.ancestor(of: badge, matching: links),
        commentStyle ? findsNothing : findsOneWidget,
      );
      expect(find.ancestor(of: body, matching: links), findsNothing);
      if (!commentStyle) {
        final naturalHeight =
            (tester.getSize(name).height + tester.getSize(time).height).clamp(
              32.0,
              double.infinity,
            );
        expect(tester.getSize(links).height, naturalHeight);
        final floor = find.descendant(of: linked, matching: find.text('#4'));
        expect(find.ancestor(of: floor, matching: links), findsNothing);
      }
    });
  }

  testWidgets('抽屉中的主题与回复按正常路由打开并返回抽屉', (tester) async {
    final repo = FixtureSpace();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: PressScale(
              onTap: () => showUserDrawer(context, '42', repository: repo),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('装机爱好者'), findsNWidgets(2));
    await tester.ensureVisible(find.text('主题与回复'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('主题与回复'));
    await tester.pumpAndSettle();
    expect(find.byType(MyThreadsPage), findsOneWidget);
    Navigator.of(tester.element(find.byType(MyThreadsPage))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(UserDrawer), findsOneWidget);
    // 返回后保留入口处滚动位置，身份卡可能已离开惰性列表。
    expect(find.text('装机爱好者'), findsWidgets);
    expect(find.text('主题与回复').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _ProfileFetcher extends ChhFetcher {
  @override
  String get name => 'offline-profile';

  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) async {
    expect(url.path, '/space-uid-4.html');
    return const ChhResponse(200, '<html><h2 class="mbn">离线用户主页</h2></html>');
  }
}
