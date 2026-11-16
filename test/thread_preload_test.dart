import 'dart:async';

import 'package:chh_app/design/theme.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/thread_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chh_app/ui/press.dart';

import 'threaded_thread_page_test.dart' as fixture;

ThreadDetail page(int number, {bool more = true}) => ThreadDetail(
  tid: 123,
  title: '预加载讨论',
  posts: [
    Post(
      pid: number,
      floor: number,
      author: '作者',
      timeRaw: '',
      content: [
        TextBlock(List.filled(number == 1 ? 100 : 2, '阅读正文').join('\n')),
      ],
    ),
  ],
  page: PageInfo(current: number, hasNext: more),
);

Future<void> mount(WidgetTester tester, ThreadPageLoader load) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      home: ThreadDetailPage(tid: 123, title: '', loadPage: load),
    ),
  );
  // Observe the first painted page before the 300ms preload window.
  await tester.pump();
  await tester.pump();
}

Future<void> tick(WidgetTester tester, [int milliseconds = 300]) async {
  await tester.pump(Duration(milliseconds: milliseconds));
  await tester.pump();
}

void main() {
  testWidgets(
    'reply expansion adopts the pending preloaded page without dropping the tap',
    (tester) async {
      final second = Completer<ThreadDetail>();
      final reads = <int>[];
      await mount(tester, (number, _, _) async {
        reads.add(number);
        return number == 1
            ? fixture.page([
                fixture.post(1),
                fixture.post(2),
                fixture.post(3, target: 2),
                fixture.post(4, long: true),
              ], more: true)
            : second.future;
      });
      await tick(tester);
      expect(reads, [1, 2]);
      final expand = find.byKey(const ValueKey('thread-expand-replies-2'));
      tester.widget<PressScale>(expand).onTap!();
      await tester.pump();
      expect(find.text('正在加载回复…'), findsOneWidget);
      second.complete(fixture.page([fixture.post(5, target: 2)], n: 2));
      await tester.pumpAndSettle();
      expect(find.text('正文5'), findsOneWidget);
      expect(reads, [1, 2]);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'first page paints before serial preload, which stops at 30 pages',
    (tester) async {
      final reads = <int>[];
      await mount(tester, (number, _, _) async {
        reads.add(number);
        return page(number);
      });
      expect(reads, [1]);
      for (var number = 2; number <= 30; number++) {
        await tick(tester, 299);
        expect(reads.length, number - 1);
        await tick(tester, 1);
        expect(reads.last, number);
        expect(reads.length, number);
      }
      await tick(tester, 10000);
      expect(reads, List.generate(30, (i) => i + 1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('failed preload retains content and waits for explicit retry', (
    tester,
  ) async {
    final reads = <int>[];
    await mount(tester, (number, _, _) async {
      reads.add(number);
      if (number == 2) throw StateError('offline');
      return page(number);
    });
    await tick(tester);
    await tick(tester, 20000);
    expect(reads, [1, 2]);
    expect(find.text('预加载讨论'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });

  for (final duplicate in [false, true]) {
    testWidgets(
      'preload stops at ${duplicate ? 'repeated content' : 'source page fallback'}',
      (tester) async {
        final reads = <int>[];
        await mount(tester, (number, _, _) async {
          reads.add(number);
          final first = page(1);
          return number == 1 || !duplicate
              ? first
              : ThreadDetail(
                  tid: first.tid,
                  title: first.title,
                  posts: first.posts,
                  page: const PageInfo(current: 2, hasNext: true),
                );
        });
        await tick(tester);
        await tick(tester, 10000);
        expect(reads, [1, 2]);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('covered routes pause preload and returning resumes it', (
    tester,
  ) async {
    final reads = <int>[];
    await mount(tester, (number, _, _) async {
      reads.add(number);
      return page(number, more: number < 2);
    });
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('另一页')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tick(tester, 5000);
    expect(reads, [1]);
    navigator.pop();
    await tester.pumpAndSettle();
    await tick(tester);
    expect(reads, [1, 2]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('navigation gesture pauses new preload until it settles', (
    tester,
  ) async {
    final reads = <int>[];
    await mount(tester, (number, _, _) async {
      reads.add(number);
      return page(number, more: number < 2);
    });
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.didStartUserGesture();
    await tick(tester, 3000);
    expect(reads, [1]);
    navigator.didStopUserGesture();
    await tick(tester, 299);
    expect(reads, [1]);
    await tick(tester, 1);
    expect(reads, [1, 2]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'arrived preload waits for return cancellation without rereading',
    (tester) async {
      final reads = <int>[];
      final second = Completer<ThreadDetail>();
      await mount(tester, (number, _, _) async {
        reads.add(number);
        return number == 1 ? page(1) : second.future;
      });
      final dynamic state = tester.state(find.byType(ThreadDetailPage));
      final snapshot = state.debugConversationIndex;
      await tick(tester);
      expect(reads, [1, 2]);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.didStartUserGesture();
      second.complete(page(2, more: false));
      await tester.pump();
      await tick(tester, 3000);
      expect(state.debugConversationIndex, same(snapshot));
      expect(state.debugConversationIndex.loadedPostCount, 1);
      expect(reads, [1, 2]);
      navigator.didStopUserGesture();
      await tester.pump();
      await tester.pump();
      expect(state.debugConversationIndex.loadedPostCount, 2);
      await tick(tester, 3000);
      expect(reads, [1, 2]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('disposing during a return drops the deferred page', (
    tester,
  ) async {
    final reads = <int>[];
    final second = Completer<ThreadDetail>();
    await mount(tester, (number, _, _) async {
      reads.add(number);
      return number == 1 ? page(1) : second.future;
    });
    await tick(tester);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.didStartUserGesture();
    second.complete(page(2));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tick(tester, 3000);
    expect(reads, [1, 2]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('background and disposal stop pending preload', (tester) async {
    final reads = <int>[];
    await mount(tester, (number, _, _) async {
      reads.add(number);
      return page(number);
    });
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tick(tester, 5000);
    expect(reads, [1]);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tick(tester);
    expect(reads, [1, 2]);
    await tester.pumpWidget(const SizedBox());
    await tick(tester, 5000);
    expect(reads, [1, 2]);
  });

  testWidgets('slow page does not overlap another preloaded page', (
    tester,
  ) async {
    final reads = <int>[];
    final second = Completer<ThreadDetail>();
    await mount(tester, (number, _, _) async {
      reads.add(number);
      return number == 2 ? second.future : page(number);
    });
    await tick(tester);
    await tick(tester, 10000);
    expect(reads, [1, 2]);
    second.complete(page(2, more: false));
    await tester.pump();
    await tick(tester, 10000);
    expect(reads, [1, 2]);
    await tester.pumpWidget(const SizedBox());
  });
}
