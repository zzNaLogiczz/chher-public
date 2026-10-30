import 'package:chh_app/data/forum_repository.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/pages/thread_detail_page.dart';
import 'package:chh_app/ui/app_button.dart';
import 'package:chh_app/ui/segmented.dart';
import 'package:chh_app/widgets/thread_comment_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'threaded_thread_page_test.dart' as fixture;

class _Forum extends ForumRepository {
  _Forum() : super(ChhClient(fetchers: []));
  final unlocked = <({int pid, String password, String prefix})>[];
  final verified = <int>[];
  bool fail = false;
  @override
  Future<void> unlockPost({
    required int pid,
    required String password,
    required String cookiePrefix,
  }) async {
    if (fail) throw StateError('offline');
    unlocked.add((pid: pid, password: password, prefix: cookiePrefix));
  }

  @override
  Future<bool> verifyForumPassword(int fid, String password) async {
    verified.add(fid);
    return password == 'correct';
  }
}

Post locked(int pid) => Post(
  pid: pid,
  floor: pid,
  author: '用户$pid',
  timeRaw: '10:00',
  content: const [],
  lock: const PostLock(text: '本帖为密码帖，请输入密码', needsPassword: true),
);

ThreadDetail data(bool unlocked) => ThreadDetail(
  tid: 123,
  title: '密码楼层',
  cookiePrefix: 'fixture_',
  posts: [
    fixture.post(20, long: true),
    unlocked ? fixture.post(21) : locked(21),
    fixture.post(22, target: 21),
    for (var n = 23; n < 40; n++) fixture.post(n),
  ],
  page: const PageInfo(current: 2, hasNext: false),
);

Future<void> enterPassword(WidgetTester tester, String password) async {
  final input = find.widgetWithText(AppButton, '输入密码').first;
  if (find.byType(Scrollable).evaluate().isNotEmpty) {
    await Scrollable.ensureVisible(tester.element(input), alignment: .3);
    await tester.pumpAndSettle();
  }
  await tester.tap(input);
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), password);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  testWidgets(
    'unlock replaces only its page and retains scroll and expanded replies',
    (tester) async {
      final repo = _Forum();
      final reads = <({int page, String? author, bool refresh})>[];
      await fixture.pump(
        tester,
        ThreadDetailPage(
          tid: 123,
          title: '密码楼层',
          initialPage: 2,
          repository: repo,
          loadPage: (page, author, refresh) async {
            reads.add((page: page, author: author, refresh: refresh));
            return data(repo.unlocked.isNotEmpty);
          },
        ),
      );
      final expand = find.byKey(const ValueKey('thread-expand-replies-21'));
      await tester.scrollUntilVisible(
        expand,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(expand);
      await tester.pumpAndSettle();
      await tester.tap(expand);
      await tester.pumpAndSettle();
      final input = find.widgetWithText(AppButton, '输入密码');
      await tester.scrollUntilVisible(
        input,
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(tester.element(input), alignment: .3);
      await tester.pumpAndSettle();
      final scroll = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      final offset = scroll.pixels;
      expect(offset, greaterThan(0));
      await enterPassword(tester, 'correct');
      expect(find.text('正文21'), findsOneWidget);
      expect(scroll.pixels, offset);
      expect(find.byKey(const ValueKey('post-22')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byType(AppSegmented<ThreadViewMode>),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester
            .widget<AppSegmented<ThreadViewMode>>(
              find.byType(AppSegmented<ThreadViewMode>),
            )
            .value,
        ThreadViewMode.threaded,
      );
      expect(reads, [
        (page: 2, author: null, refresh: false),
        (page: 2, author: null, refresh: true),
      ]);
      expect(repo.unlocked.single, (
        pid: 21,
        password: 'correct',
        prefix: 'fixture_',
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'still locked reports an incorrect password without clearing the page',
    (tester) async {
      final repo = _Forum();
      await fixture.pump(
        tester,
        ThreadDetailPage(
          tid: 123,
          title: '密码楼层',
          initialPage: 2,
          repository: repo,
          loadPage: (_, _, _) async => data(false),
        ),
      );
      await tester.scrollUntilVisible(
        find.widgetWithText(AppButton, '输入密码'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await enterPassword(tester, 'wrong');
      expect(find.text('密码不正确'), findsOneWidget);
      expect(find.text('本帖为密码帖，请输入密码'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unlock in author mode also updates the saved normal view', (
    tester,
  ) async {
    final repo = _Forum();
    final reads = <String?>[];
    await fixture.pump(
      tester,
      ThreadDetailPage(
        tid: 123,
        title: '作者视图解锁',
        repository: repo,
        loadPage: (_, author, _) async {
          reads.add(author);
          return ThreadDetail(
            tid: 123,
            title: '作者视图解锁',
            cookiePrefix: 'fixture_',
            posts: [
              fixture.post(1),
              if (repo.unlocked.isNotEmpty)
                fixture.post(2, uid: '1')
              else
                const Post(
                  pid: 2,
                  floor: 2,
                  author: '用户1',
                  authorUid: '1',
                  timeRaw: '',
                  content: [],
                  lock: PostLock(text: '本帖为密码帖，请输入密码', needsPassword: true),
                ),
              if (author == null) fixture.post(3),
            ],
            page: const PageInfo(current: 1, hasNext: false),
          );
        },
      ),
    );
    await fixture.tapViewMode(tester, '只看楼主');
    await tester.pumpAndSettle();
    expect(reads, [null, '1']);
    await enterPassword(tester, 'correct');
    expect(find.text('正文2'), findsOneWidget);
    expect(reads, [null, '1', '1']);
    await fixture.tapViewMode(tester, '原楼层');
    await tester.pumpAndSettle();
    expect(find.text('正文2'), findsOneWidget);
    expect(find.text('本帖为密码帖，请输入密码'), findsNothing);
    expect(reads, [null, '1', '1']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed unlock reports retry and retains the locked floor', (
    tester,
  ) async {
    final repo = _Forum()..fail = true;
    await fixture.pump(
      tester,
      ThreadDetailPage(
        tid: 123,
        title: '密码楼层',
        repository: repo,
        loadPage: (_, _, _) async => ThreadDetail(
          tid: 123,
          title: '密码楼层',
          cookiePrefix: 'fixture_',
          posts: [locked(1)],
          page: const PageInfo(current: 1, hasNext: false),
        ),
      ),
    );
    await enterPassword(tester, 'correct');
    expect(find.text('解锁未完成，请重试'), findsOneWidget);
    expect(find.text('本帖为密码帖，请输入密码'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets(
    'forum password state reloads thread after successful verification',
    (tester) async {
      final repo = _Forum();
      var reads = 0;
      await fixture.pump(
        tester,
        ThreadDetailPage(
          tid: 123,
          title: '密码版块',
          repository: repo,
          loadPage: (_, _, refresh) async {
            reads++;
            if (repo.verified.isEmpty) {
              throw const PageMessage(
                PageMessageKind.forumPassword,
                '站点原文',
                fid: 316,
              );
            }
            expect(refresh, isTrue);
            return fixture.page([fixture.post(1)]);
          },
        ),
      );
      expect(find.text('本版块需要密码'), findsOneWidget);
      await enterPassword(tester, 'correct');
      expect(repo.verified, [316]);
      expect(reads, 2);
      expect(find.text('正文1'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
