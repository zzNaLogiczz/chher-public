import 'dart:async';

import 'package:chh_app/models/models.dart';
import 'package:chh_app/widgets/post_card.dart';
import 'package:chh_app/widgets/rich_content_text.dart';
import 'package:chh_app/pages/thread_detail_page.dart';
import 'package:chh_app/ui/segmented.dart';
import 'package:chh_app/widgets/thread_comment_widgets.dart';
import 'package:chh_app/ui/reading_bar.dart';
import 'package:chh_app/ui/app_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'threaded_thread_page_test.dart' as fixture;

Future<void> expand(WidgetTester tester) async {
  final action = find.byKey(const ValueKey('thread-expand-replies-2'));
  await tester.scrollUntilVisible(
    action,
    250,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 100,
  );
  await Scrollable.ensureVisible(tester.element(action), alignment: .4);
  await tester.pump();
  await tester.tap(action);
  await tester.pumpAndSettle();
}

Future<void> tapViewMode(WidgetTester tester, String label) async {
  final segment = find.descendant(
    of: find.byType(AppSegmented<ThreadViewMode>),
    matching: find.text(label),
  );
  await tester.ensureVisible(segment);
  await tester.pump();
  await tester.tap(segment);
}

Future<ThreadViewMode> currentViewMode(WidgetTester tester) async {
  final segmented = find.byType(AppSegmented<ThreadViewMode>);
  await tester.scrollUntilVisible(
    segmented,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  return tester.widget<AppSegmented<ThreadViewMode>>(segmented).value;
}

void main() {
  testWidgets(
    'new replies grow downward without moving the root or replaying old replies',
    (tester) async {
      var reads = 0;
      await fixture.pump(
        tester,
        ThreadDetailPage(
          tid: 123,
          title: '展开动效',
          loadPage: (_, _, _) async {
            reads++;
            return fixture.page([
              fixture.post(1),
              fixture.post(2),
              for (var n = 3; n <= 14; n++) fixture.post(n, target: 2),
            ]);
          },
        ),
      );
      final action = find.byKey(const ValueKey('thread-expand-replies-2'));
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      final root = find.byKey(const ValueKey('post-2'));
      final rootTop = tester.getTopLeft(root);
      final scroll = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      final offset = scroll.pixels;
      final onExpand = tester.widget<AppButton>(action).onPressed!;
      onExpand();
      onExpand(); // A rapid second activation must not append another batch.
      await tester.pump();
      final first = find.byKey(const ValueKey('post-3'));
      expect(tester.getSize(first).height, 0);
      await tester.pump(const Duration(milliseconds: 70));
      final middleHeight = tester.getSize(first).height;
      expect(middleHeight, greaterThan(0));
      expect(tester.getTopLeft(root), rootTop);
      expect(scroll.pixels, offset);
      await tester.pumpAndSettle();
      expect(tester.getSize(first).height, greaterThan(middleHeight));
      await fixture.bottom(tester);
      expect(find.text('展开更多回复（2）'), findsOneWidget);
      final previousReply = find.byKey(const ValueKey('post-12'));
      final previousHeight = tester.getSize(previousReply).height;
      await tester.tap(action);
      await tester.pump();
      expect(tester.getSize(previousReply).height, previousHeight);
      expect(tester.getSize(find.byKey(const ValueKey('post-13'))).height, 0);
      await tester.pumpAndSettle();
      expect(reads, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reduced motion reveals replies immediately', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await fixture.pump(
      tester,
      ThreadDetailPage(
        tid: 123,
        title: '减少动态效果',
        loadPage: (_, _, _) async => fixture.page([
          fixture.post(1),
          fixture.post(2),
          fixture.post(3, target: 2),
        ]),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('thread-expand-replies-2')));
    await tester.pump();
    final first = find.byKey(const ValueKey('post-3'));
    final height = tester.getSize(first).height;
    expect(height, greaterThan(0));
    await tester.pump(const Duration(milliseconds: 70));
    expect(tester.getSize(first).height, height);
    await fixture.bottom(tester);
    // 样例内容不足一屏,圆钮停在"查看评论";减少动态效果下点击也只做直接跳转
    await tester.tap(find.byKey(ReadingBar.actionKey));
    await tester.pump();
    expect(
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .pixels,
      0,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the first expansion frame keeps a thousand-block reply lazy', (
    tester,
  ) async {
    await fixture.pump(
      tester,
      ThreadDetailPage(
        tid: 123,
        title: '长回复动效',
        loadPage: (_, _, _) async => fixture.page([
          fixture.post(1),
          fixture.post(2),
          Post(
            pid: 3,
            floor: 3,
            author: '长回复',
            timeRaw: '',
            content: [
              fixture.post(3, target: 2).content.first,
              for (var n = 0; n < 1000; n++) TextBlock('段落$n'),
            ],
          ),
        ]),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('thread-expand-replies-2')));
    await tester.pump();
    expect(fixture.card(3).evaluate().length, lessThan(60));
    expect(find.text('段落999'), findsNothing);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('only replies to another child name their direct recipient', (
    tester,
  ) async {
    await fixture.pump(
      tester,
      ThreadDetailPage(
        tid: 123,
        title: '回复对象',
        loadPage: (_, _, _) async => fixture.page([
          fixture.post(1),
          fixture.post(2),
          fixture.post(3, target: 2),
          fixture.post(4, target: 3),
          fixture.post(5, target: 4),
          fixture.post(6, target: 2),
        ]),
      ),
    );
    await expand(tester);
    await tester.scrollUntilVisible(
      find.text('回复 用户3：正文4'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('回复 用户3：正文4'), findsOneWidget);
    expect(find.text('回复 用户2：正文3'), findsNothing);
    expect(find.text('保留的原始引用'), findsNothing);
    await fixture.bottom(tester);
    expect(find.text('回复 用户4：正文5'), findsOneWidget);
    expect(find.text('正文6'), findsOneWidget);
    expect(find.text('回复 用户2：正文6'), findsNothing);
    await tapViewMode(tester, '原楼层');
    await tester.pumpAndSettle();
    await fixture.bottom(tester);
    expect(find.text('回复 用户4：正文5'), findsNothing);
    expect(find.text('正文5'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long replies prefix only their first lazy content block', (
    tester,
  ) async {
    await fixture.pump(
      tester,
      ThreadDetailPage(
        tid: 123,
        title: '长回复',
        loadPage: (_, _, _) async => fixture.page([
          fixture.post(1),
          fixture.post(2),
          fixture.post(3, target: 2),
          Post(
            pid: 4,
            floor: 4,
            author: '用户4',
            timeRaw: '',
            content: [
              fixture.post(4, target: 3).content.first,
              for (var i = 0; i < 13; i++) TextBlock('第$i段'),
            ],
          ),
        ]),
      ),
    );
    await expand(tester);
    await tester.scrollUntilVisible(
      find.text('回复 用户3：第0段'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('回复 用户3：第0段'), findsOneWidget);
    await fixture.bottom(tester);
    expect(find.text('第12段'), findsOneWidget);
    expect(find.text('回复 用户3：第12段'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'recipient prefix preserves inline emoji and image-only replies',
    (tester) async {
      const smiley = InlineSmiley('https://invalid.example/smile.png');
      for (final content in <List<ContentBlock>>[
        const [
          TextBlock('你好', nodes: [InlineText('你好'), smiley]),
        ],
        const [ImageBlock('https://invalid.example/image.png')],
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: PostCard(
                  post: Post(
                    pid: 4,
                    floor: 4,
                    author: 'C',
                    timeRaw: '',
                    content: content,
                  ),
                  isOpening: false,
                  commentStyle: true,
                  replyToAuthor: 'B',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final body = tester.widget<RichContentText>(
          find.byType(RichContentText),
        );
        expect(body.block.text, startsWith('回复 B：'));
        if (content.first is TextBlock) {
          expect(
            body.block.nodes.whereType<InlineSmiley>().single,
            same(smiley),
          );
          expect((content.first as TextBlock).text, '你好');
        }
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('replies expand inline ten at a time without quoted text', (
    tester,
  ) async {
    var reads = 0;
    await fixture.pump(
      tester,
      ThreadDetailPage(
        tid: 123,
        title: '分批回复',
        loadPage: (_, _, _) async {
          reads++;
          return fixture.page([
            fixture.post(1),
            fixture.post(2, target: 1),
            for (var n = 3; n <= 27; n++) fixture.post(n, target: n - 1),
          ]);
        },
      ),
    );
    expect(find.text('保留的原始引用'), findsNothing);
    expect(fixture.card(3), findsNothing);
    await expand(tester);
    await fixture.bottom(tester);
    expect(find.text('展开更多回复（15）'), findsOneWidget);
    expect(fixture.card(13), findsNothing);
    await expand(tester);
    await fixture.bottom(tester);
    expect(find.text('展开更多回复（5）'), findsOneWidget);
    expect(fixture.card(23), findsNothing);
    await expand(tester);
    await fixture.bottom(tester);
    expect(find.text('回复 用户26：正文27'), findsOneWidget);
    expect(find.byKey(const ValueKey('thread-expand-replies-2')), findsNothing);
    expect(reads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'inline loading retries a failed page and ignores repeated taps',
    (tester) async {
      final pending = Completer<void>();
      final reads = <int>[];
      var attempts = 0;
      await fixture.pump(
        tester,
        ThreadDetailPage(
          tid: 123,
          title: '按需加载',
          loadPage: (n, _, _) async {
            reads.add(n);
            if (n == 1) {
              return fixture.page([
                fixture.post(1, long: true),
                fixture.post(2),
                fixture.post(3, target: 2),
              ], more: true);
            }
            if (attempts++ == 0) {
              await pending.future;
              throw StateError('offline');
            }
            return fixture.page([
              for (var id = 4; id <= 16; id++) fixture.post(id, target: 2),
            ], n: 2);
          },
        ),
      );
      final action = find.byKey(const ValueKey('thread-expand-replies-2'));
      await tester.scrollUntilVisible(
        action,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(tester.element(action), alignment: .4);
      await tester.pump();
      // If proximity loading already started, the control must stay disabled.
      final callback = tester.widget<AppButton>(action).onPressed;
      callback?.call();
      callback?.call();
      await tester.pump();
      expect(reads, [1, 2]);
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('回复加载失败，点击重试'), findsOneWidget);
      await expand(tester);
      await fixture.bottom(tester);
      expect(reads, [1, 2, 2]);
      expect(find.text('展开更多回复（4）'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
