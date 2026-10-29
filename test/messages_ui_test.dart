/// Interaction checks use a fake repository; no real private messages are sent.
library;

import 'dart:async';

import 'package:chh_app/data/message_repository.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/di.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/pages/messages_page.dart';
import 'package:chh_app/pages/pm_thread_page.dart';
import 'package:chh_app/parser/header_parser.dart';
import 'package:chh_app/ui/picker.dart';
import 'package:chh_app/ui/chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const pmFixture = PmConversation(
  id: 'conversation-1',
  peer: '对方',
  preview: '最近一条消息',
  timeRaw: '2026-10-26 10:30',
  viewUrl:
      'https://www.chiphell.com/home.php?mod=space&do=pm&subop=view&plid=1',
);
const notice = Notice(
  id: 'notice-1',
  category: 'post',
  actor: '坛友',
  occurredAtText: '2026-10-26 10:30',
  summary: '坛友回复了你的装机帖',
  tid: 123,
  pid: 987,
  targetUrl:
      'https://www.chiphell.com/forum.php?mod=redirect&goto=findpost&ptid=123&pid=987',
);

class FakeMessages extends MessageRepository {
  int sends = 0;
  int reads = 0;
  int nextReads = 0;
  bool more = false;
  bool failNext = false;
  Object? readError;
  Completer<PostResult>? pending;
  PostResult response = const PostResult(PostResultKind.failed, '站点暂时无法发送');
  NoticeView? lastView;
  String? lastType;
  PmFilter? lastPm;
  bool emptyNotices = false;
  FakeMessages() : super(ChhClient(fetchers: []));
  @override
  Future<List<PmMessage>> conversation(
    String viewUrl, {
    bool refresh = true,
  }) async {
    reads++;
    if (readError != null) throw readError!;
    return const [
      PmMessage(
        author: '对方',
        authorUid: '2',
        timeRaw: '2026-10-26 10:30',
        text: '你好，这个配置看起来不错。',
      ),
    ];
  }

  @override
  Future<PostResult> reply({
    required String viewUrl,
    required String message,
  }) async {
    sends++;
    return pending != null ? pending!.future : response;
  }

  @override
  Future<Paged<Notice>> notices({
    NoticeView view = NoticeView.all,
    String? type,
    int page = 1,
    bool refresh = false,
  }) async {
    lastView = view;
    lastType = type;
    return Paged(
      items: emptyNotices ? const [] : const [notice],
      page: PageInfo(current: page, hasNext: more),
      nextUrl: more
          ? 'https://www.chiphell.com/home.php?mod=space&do=notice&page=2&isread=1'
          : null,
    );
  }

  @override
  Future<Paged<Notice>> noticesNext(
    Paged<Notice> previous, {
    bool refresh = false,
  }) async {
    nextReads++;
    if (failNext) throw StateError('offline');
    return const Paged(items: [], page: PageInfo(current: 2, hasNext: false));
  }

  @override
  Future<Paged<PmConversation>> conversations({
    PmFilter filter = PmFilter.privatePm,
    int page = 1,
    bool refresh = false,
  }) async {
    lastPm = filter;
    return Paged(
      items: const [pmFixture],
      page: PageInfo(current: page, hasNext: false),
    );
  }
}

Widget app(Widget child) =>
    MaterialApp(theme: buildAppTheme(Brightness.light), home: child);
Future<void> showPm(WidgetTester tester, FakeMessages repository) async {
  await tester.pumpWidget(
    app(PmThreadPage(conversation: pmFixture, repository: repository)),
  );
  await tester.pumpAndSettle();
}

void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  chatButtonTests();
  testWidgets('switching sections keeps both lists instead of reloading', (
    tester,
  ) async {
    phone(tester);
    final repository = _CountingMessages();
    await tester.pumpWidget(
      app(Scaffold(body: MessagesBody(repository: repository))),
    );
    await tester.pumpAndSettle();
    expect(repository.noticeReads, 1);
    // 私信列表在第一次切过去之前不加载
    expect(repository.pmReads, 0);
    await tester.tap(find.text('私信'));
    await tester.pumpAndSettle();
    expect(repository.pmReads, 1);
    await tester.tap(find.text('提醒'));
    await tester.pump();
    // 切回来是原来的列表:不重新请求,也不再做整列表淡入
    expect(repository.noticeReads, 1);
    final fading = tester
        .widgetList<Opacity>(
          find.ancestor(
            of: find.text(notice.summary).hitTestable(),
            matching: find.byType(Opacity),
          ),
        )
        .where((o) => o.opacity < 1);
    expect(fading, isEmpty);
    await tester.tap(find.text('私信'));
    await tester.pumpAndSettle();
    expect(repository.pmReads, 1);
  });
  testWidgets('a message the source marks as yours is your bubble', (
    tester,
  ) async {
    phone(tester);
    await showPm(tester, _SelfMarked());
    final bubble = tester.widget<ChatBubble>(
      find.ancestor(
        of: find.text('可以先看看实物'),
        matching: find.byType(ChatBubble),
      ),
    );
    expect(bubble.mine, isTrue);
    expect(tester.getCenter(find.text('可以先看看实物')).dx, greaterThan(195));
  });
  testWidgets('conversation title centers the peer name', (tester) async {
    phone(tester);
    await showPm(tester, FakeMessages());
    final name = tester.getCenter(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text(pmFixture.peer),
      ),
    );
    expect(name.dx, moreOrLessEquals(195, epsilon: 1));
  });
  test('notification route preserves exact source redirect and floor ID', () {
    final target = noticeThreadTarget(notice)!;
    expect(target.tid, 123);
    expect(target.gotoUrl, notice.targetUrl);
    expect(target.focusPid, 987);
    expect(
      noticeThreadTarget(
        const Notice(
          id: 's',
          category: 'system',
          occurredAtText: '',
          summary: '系统公告',
        ),
      ),
      isNull,
    );
  });

  testWidgets(
    'failed send retains draft and rapid repeat cannot submit twice',
    (tester) async {
      phone(tester);
      final repository = FakeMessages()..pending = Completer<PostResult>();
      await showPm(tester, repository);
      await tester.enterText(
        find.byKey(const ValueKey('pm-input')),
        '请问电源的具体型号？',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pm-send')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pm-send')));
      await tester.pump();
      expect(repository.sends, 1);
      repository.pending!.complete(
        const PostResult(PostResultKind.failed, '站点暂时无法发送'),
      );
      await tester.pumpAndSettle();
      expect(find.text('站点暂时无法发送'), findsOneWidget);
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('pm-input')),
      );
      expect(field.controller!.text, '请问电源的具体型号？');
      expect(repository.reads, 1);
    },
  );

  testWidgets(
    'uncertain result keeps text and offers refresh without auto resend',
    (tester) async {
      final repository = FakeMessages()
        ..response = const PostResult(PostResultKind.unknown, 'unknown');
      await showPm(tester, repository);
      await tester.enterText(find.byKey(const ValueKey('pm-input')), '未确认的消息');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pm-send')));
      await tester.pumpAndSettle();
      expect(find.textContaining('发送结果未确认'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('pm-input')))
            .controller!
            .text,
        '未确认的消息',
      );
      await tester.pump();
      expect(repository.sends, 1);
      await tester.tap(find.text('刷新'));
      await tester.pumpAndSettle();
      expect(repository.reads, 2);
      expect(repository.sends, 1);
    },
  );

  testWidgets('confirmed success clears input and reloads conversation', (
    tester,
  ) async {
    final repository = FakeMessages()
      ..response = const PostResult(PostResultKind.success, '发送成功');
    await showPm(tester, repository);
    await tester.enterText(find.byKey(const ValueKey('pm-input')), '谢谢分享');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pm-send')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('pm-input')))
          .controller!
          .text,
      isEmpty,
    );
    expect(repository.reads, 2);
    expect(repository.sends, 1);
  });

  testWidgets(
    'composer stays above keyboard and public messages have no send affordance',
    (tester) async {
      phone(tester);
      final repository = FakeMessages();
      await showPm(tester, repository);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      expect(
        tester.getRect(find.byKey(const ValueKey('pm-input'))).bottom,
        lessThanOrEqualTo(844 - 280),
      );
      await tester.pumpWidget(
        app(
          PmThreadPage(
            repository: repository,
            conversation: const PmConversation(
              id: 'g1',
              peer: '公共公告',
              preview: '',
              timeRaw: '',
              viewUrl:
                  'https://www.chiphell.com/home.php?mod=space&do=pm&subop=viewg&pmid=1',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pm-send')), findsNothing);
    },
  );

  testWidgets(
    'server counters and all notification/private/public filters remain available',
    (tester) async {
      final previous = chhSession.badges;
      addTearDown(() => chhSession.badges = previous);
      chhSession.badges = const HeaderBadges(notices: 3, messages: 2);
      final repository = FakeMessages();
      await tester.pumpWidget(
        app(Scaffold(body: MessagesBody(repository: repository))),
      );
      await tester.pumpAndSettle();
      expect(find.text('提醒 3'), findsOneWidget);
      expect(find.text('私信 2'), findsOneWidget);
      Future<void> pick(String current, String next) async {
        await tester.tap(find.text(current));
        await tester.pumpAndSettle();
        await tester.tap(find.text(next).last);
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pumpAndSettle();
      }

      await pick('全部', '我的帖子');
      expect(repository.lastView, NoticeView.mypost);
      await pick('全部类型', '点评');
      expect(repository.lastType, 'pcomment');
      await pick('点评', '全部类型');
      expect(repository.lastType, isNull);
      await pick('我的帖子', '应用');
      expect(repository.lastView, NoticeView.app);
      await tester.tap(find.text('私信 2'));
      await tester.pumpAndSettle();
      expect(repository.lastPm, PmFilter.privatePm);
      await pick('私人消息', '公共消息');
      expect(repository.lastPm, PmFilter.announcePm);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'notice type picker sits in the first date row and survives an empty list',
    (tester) async {
      final repository = FakeMessages();
      await tester.pumpWidget(
        app(Scaffold(body: MessagesBody(repository: repository))),
      );
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('message-filter-row'));
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.byType(PickerButton<int>)),
        findsOneWidget,
      );
      // 日期与选择按钮同一行
      expect(
        find.descendant(of: row, matching: find.byType(Text)),
        findsWidgets,
      );

      repository.emptyNotices = true;
      await tester.tap(find.text('全部'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('系统').last);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.text('暂时没有提醒'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('message-filter-row')),
          matching: find.text('系统'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'pagination failure preserves existing messages and allows explicit retry',
    (tester) async {
      final repository = FakeMessages()
        ..more = true
        ..failNext = true;
      await tester.pumpWidget(
        app(Scaffold(body: MessagesBody(repository: repository))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('加载更多'));
      await tester.pumpAndSettle();
      expect(find.text('坛友回复了你的装机帖'), findsOneWidget);
      expect(find.text('未能加载更多，轻点重试'), findsOneWidget);
      repository.failNext = false;
      await tester.tap(find.text('未能加载更多，轻点重试'));
      await tester.pumpAndSettle();
      expect(repository.nextReads, 2);
      expect(find.text('已显示全部消息'), findsOneWidget);
    },
  );

  testWidgets('login state offers an actionable login route', (tester) async {
    final repository = FakeMessages()
      ..readError = const PageMessage(PageMessageKind.loginRequired, '请先登录');
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        routes: {'/login': (_) => const Scaffold(body: Text('登录页面'))},
        home: PmThreadPage(conversation: pmFixture, repository: repository),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('登录后查看消息'), findsOneWidget);
    await tester.tap(find.text('登录'));
    await tester.pumpAndSettle();
    expect(find.text('登录页面'), findsOneWidget);
  });
}

void chatButtonTests() {
  testWidgets('pm send button pops in only with text', (tester) async {
    Widget button(bool visible) => MaterialApp(
      theme: buildAppTheme(Brightness.light),
      home: Scaffold(
        body: Center(
          child: ChatSendButton(
            visible: visible,
            sending: false,
            onPressed: () {},
          ),
        ),
      ),
    );
    await tester.pumpWidget(button(false));
    await tester.pumpAndSettle();
    double scale() => tester
        .widget<Transform>(
          find
              .descendant(
                of: find.byType(ChatSendButton),
                matching: find.byType(Transform),
              )
              .first,
        )
        .transform
        .storage[0];
    expect(scale(), 0);
    await tester.pumpWidget(button(true));
    await tester.pumpAndSettle();
    expect(scale(), closeTo(1, .001));
  });
}

/// 会话里自己那条:源站标成"您",没有可比对的会话 UID 时也要认出来
class _SelfMarked extends FakeMessages {
  @override
  Future<List<PmMessage>> conversation(
    String viewUrl, {
    bool refresh = true,
  }) async => const [
    PmMessage(
      author: '您',
      timeRaw: '2026-6-30 10:53',
      text: '可以先看看实物',
      fromSelf: true,
    ),
  ];
}

class _CountingMessages extends FakeMessages {
  int noticeReads = 0;
  int pmReads = 0;
  @override
  Future<Paged<Notice>> notices({
    NoticeView view = NoticeView.all,
    String? type,
    int page = 1,
    bool refresh = false,
  }) {
    noticeReads++;
    return super.notices(view: view, type: type, page: page, refresh: refresh);
  }

  @override
  Future<Paged<PmConversation>> conversations({
    PmFilter filter = PmFilter.privatePm,
    int page = 1,
    bool refresh = false,
  }) {
    pmReads++;
    return super.conversations(filter: filter, page: page, refresh: refresh);
  }
}
