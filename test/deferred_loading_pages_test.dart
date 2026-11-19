import 'package:chh_app/widgets/chhers_loader.dart';
import 'dart:async';

import 'package:chh_app/design/theme.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/messages_page.dart';
import 'package:chh_app/pages/thread_detail_page.dart';
import 'package:chh_app/ui/feedback.dart';
import 'package:chh_app/widgets/chhers_refresh_indicator.dart';
import 'package:chh_app/widgets/browse_thread_list.dart';
import 'package:chh_app/widgets/lacquer_tab_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'messages_ui_test.dart' show FakeMessages, notice;

class _Messages extends FakeMessages {
  final Future<Paged<Notice>> Function() read;
  _Messages(this.read);

  @override
  Future<Paged<Notice>> notices({
    NoticeView view = NoticeView.all,
    String? type,
    int page = 1,
    bool refresh = false,
  }) => read();
}

typedef _Scenario = ({
  Widget page,
  String content,
  void Function() complete,
  void Function() next,
  void Function() fail,
});

_Scenario _scenario<T>(
  Widget Function(Future<T> Function()) page,
  T result,
  String content,
) {
  var pending = Completer<T>();
  return (
    page: page(() => pending.future),
    content: content,
    complete: () => pending.complete(result),
    next: () => pending = Completer<T>(),
    fail: () => pending.completeError(StateError('offline')),
  );
}

_Scenario _list() => _scenario<Paged<ThreadSummary>>(
  (read) => Scaffold(
    body: BrowseThreadList(
      loader: (_, {bool refresh = false}) => read(),
      itemBuilder: (_, item) => Text(item.title),
    ),
  ),
  const Paged(
    items: [
      ThreadSummary(
        tid: 123,
        title: '列表内容',
        author: '样例',
        replies: 0,
        views: 0,
      ),
    ],
    page: PageInfo(current: 1, hasNext: false),
  ),
  '列表内容',
);

_Scenario _thread() => _scenario<ThreadDetail>(
  (read) =>
      ThreadDetailPage(tid: 123, title: '帖子标题', loadPage: (_, _, _) => read()),
  const ThreadDetail(
    tid: 123,
    title: '帖子标题',
    replyCount: 0,
    posts: [
      Post(
        pid: 1,
        floor: 1,
        author: '样例',
        timeRaw: '2026-11-17 10:00',
        content: [TextBlock('帖子正文')],
      ),
    ],
    page: PageInfo(current: 1, hasNext: false),
  ),
  '帖子正文',
);

_Scenario _messages() => _scenario<Paged<Notice>>(
  (read) => Scaffold(body: MessagesTabPage(repository: _Messages(read))),
  const Paged(items: [notice], page: PageInfo(current: 1, hasNext: false)),
  '坛友',
);

Future<void> _mount(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(theme: buildAppTheme(Brightness.light), home: page),
  );
  await tester.pump();
}

Finder get _placeholder => find.byWidgetPredicate(
  (widget) =>
      widget is LoadingPlaceholder ||
      widget is ChhersLoader && widget.size == ChhersLoaderSize.page,
);

bool _visible(WidgetTester tester) =>
    find
        .descendant(
          of: find.byWidgetPredicate(
            (widget) =>
                widget is ChhersLoader && widget.size == ChhersLoaderSize.page,
          ),
          matching: find.byType(CustomPaint),
        )
        .evaluate()
        .isNotEmpty ||
    tester
        .widgetList<Visibility>(
          find.descendant(
            of: find.byType(LoadingPlaceholder),
            matching: find.byType(Visibility),
          ),
        )
        .any((widget) => widget.visible);

void main() {
  for (final (name, create) in [
    ('thread list', _list),
    ('thread detail', _thread),
    ('messages', _messages),
  ]) {
    testWidgets(
      '$name fast cold read skips placeholder and refresh keeps rows',
      (tester) async {
        final scene = create();
        await _mount(tester, scene.page);
        expect(_placeholder, findsOneWidget);
        expect(_visible(tester), isFalse);
        await tester.pump(const Duration(milliseconds: 120));
        expect(_visible(tester), isFalse);
        scene.complete();
        await tester.pump();
        await tester.pump();
        expect(find.textContaining(scene.content), findsWidgets);
        expect(_placeholder, findsNothing);
        await tester.pumpAndSettle();

        scene.next();
        final refresh = name == 'messages'
            ? tester
                  .widget<LacquerTabScaffold>(
                    find.byType(LacquerTabScaffold).first,
                  )
                  .onRefresh!()
            : tester
                  .widget<ChhersRefreshIndicator>(
                    find.byType(ChhersRefreshIndicator).first,
                  )
                  .onRefresh();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.textContaining(scene.content), findsWidgets);
        expect(_placeholder, findsNothing);
        scene.complete();
        await refresh;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$name slow cold read shows placeholder until content arrives',
      (tester) async {
        final scene = create();
        await _mount(tester, scene.page);
        await tester.pump(const Duration(milliseconds: 299));
        expect(_visible(tester), isFalse);
        await tester.pump(const Duration(milliseconds: 1));
        expect(_visible(tester), isTrue);
        scene.complete();
        await tester.pumpAndSettle();
        expect(find.textContaining(scene.content), findsWidgets);
        expect(_placeholder, findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('$name failed cold read removes placeholder and allows retry', (
      tester,
    ) async {
      final scene = create();
      await _mount(tester, scene.page);
      await tester.pump(const Duration(milliseconds: 300));
      expect(_visible(tester), isTrue);
      scene.fail();
      await tester.pumpAndSettle();
      expect(_placeholder, findsNothing);
      expect(find.text('加载失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      scene.next();
      await tester.tap(find.text('重试'));
      await tester.pump();
      expect(_visible(tester), isFalse);
      scene.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining(scene.content), findsWidgets);
      expect(_placeholder, findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
