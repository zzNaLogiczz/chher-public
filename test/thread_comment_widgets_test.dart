import 'dart:collection';

import 'package:chh_app/design/theme.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/widgets/thread_comment_widgets.dart';
import 'package:chh_app/ui/segmented.dart';
import 'package:chh_app/ui/press.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Post _post(int pid, {String? author, List<ContentBlock> content = const []}) =>
    Post(
      pid: pid,
      floor: pid,
      author: author ?? '读者 $pid',
      timeRaw: '',
      content: content,
    );

Widget _app(Widget child, {bool large = false}) => MaterialApp(
  theme: buildAppTheme(large ? Brightness.dark : Brightness.light),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(large ? 1.8 : 1)),
    child: child!,
  ),
  home: Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: child,
    ),
  ),
);

String _summary(WidgetTester tester, int pid, int position) {
  final text = tester.widget<Text>(
    find.byKey(ValueKey('thread-reply-summary-$pid-$position')),
  );
  return (text.textSpan! as TextSpan).children!.last.toPlainText();
}

class _LargeReplies extends ListBase<Post> {
  final reads = <int>[];
  @override
  int get length => 10000;
  @override
  set length(int value) => throw UnsupportedError('read only');
  @override
  Post operator [](int index) {
    reads.add(index);
    if (index > 1) {
      throw StateError('A strip must not build every loaded reply');
    }
    return _post(600 + index, content: [TextBlock('预览 $index')]);
  }

  @override
  void operator []=(int index, Post value) =>
      throw UnsupportedError('read only');
}

void main() {
  testWidgets(
    'mode selection reports only changes and count never includes an extra opening post',
    (tester) async {
      var mode = ThreadViewMode.threaded;
      final changes = <ThreadViewMode>[];
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (_, update) => ThreadCommentHeading(
              loadedCount: 2,
              complete: false,
              mode: mode,
              onModeChanged: (value) => update(() {
                mode = value;
                changes.add(value);
              }),
            ),
          ),
        ),
      );
      expect(find.text('已加载 2'), findsOneWidget);
      Finder segment(String label) => find.descendant(
        of: find.byType(AppSegmented<ThreadViewMode>),
        matching: find.text(label),
      );
      await tester.tap(segment('评论'));
      await tester.pumpAndSettle();
      expect(changes, isEmpty);
      await tester.tap(segment('原楼层'));
      await tester.pumpAndSettle();
      await tester.tap(segment('只看楼主'));
      await tester.pumpAndSettle();
      await tester.tap(segment('评论'));
      await tester.pumpAndSettle();
      expect(changes, [
        ThreadViewMode.floors,
        ThreadViewMode.author,
        ThreadViewMode.threaded,
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a complete loaded set may use a complete count', (tester) async {
    await tester.pumpWidget(
      _app(
        ThreadCommentHeading(
          loadedCount: 5,
          complete: true,
          mode: ThreadViewMode.threaded,
          onModeChanged: (_) {},
        ),
      ),
    );
    expect(find.text('5'), findsOneWidget);
    expect(find.textContaining('已加载'), findsNothing);
  });

  testWidgets(
    'ten thousand replies still build exactly two previews and a loaded-count action',
    (tester) async {
      final replies = _LargeReplies();
      await tester.pumpWidget(
        _app(
          ThreadReplyStrip(replies: replies, onOpen: (_) {}, onOpenAll: () {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(replies.reads, [0, 1]);
      expect(
        find.byKey(const ValueKey('thread-reply-summary-600-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('thread-reply-summary-601-1')),
        findsOneWidget,
      );
      expect(find.text('查看已加载的 10000 条回复'), findsOneWidget);
      expect(find.byType(PressScale), findsNWidgets(3));
    },
  );

  testWidgets(
    'previews ignore quotes and stop at 120 graphemes without fetching images',
    (tester) async {
      final long = List.filled(5000, '🙂中文').join();
      await tester.pumpWidget(
        _app(
          ThreadReplyStrip(
            replies: [
              _post(
                7,
                content: [
                  const QuoteBlock([TextBlock('不能当作新回复的引文')], source: '不可信名字'),
                  TextBlock(long),
                  const ImageBlock('https://invalid.example/image.jpg'),
                ],
              ),
            ],
            onOpen: (_) {},
            onOpenAll: () {},
          ),
        ),
      );
      final text = _summary(tester, 7, 0);
      expect(text.characters.length, 120);
      expect(text, startsWith('🙂中文'));
      expect(text, isNot(contains('引文')));
      expect(find.textContaining('不可信名字'), findsNothing);
      expect(find.byType(Image), findsNothing);
    },
  );

  testWidgets(
    'root images and contentless quoted replies have honest fallback labels',
    (tester) async {
      await tester.pumpWidget(
        _app(
          ThreadReplyStrip(
            replies: [
              _post(
                1,
                content: const [
                  ImageBlock('https://invalid.example/image.jpg'),
                ],
              ),
              _post(
                2,
                content: const [
                  QuoteBlock([TextBlock('仅有被引用内容')]),
                ],
              ),
            ],
            onOpen: (_) {},
            onOpenAll: () {},
          ),
        ),
      );
      expect(_summary(tester, 1, 0), '图片回复');
      expect(_summary(tester, 2, 1), '查看回复');
      expect(find.byType(Image), findsNothing);
    },
  );

  testWidgets(
    'preview preserves the selected post and optional footer can be hidden',
    (tester) async {
      Post? selected;
      var openedAll = 0;
      final replies = [
        _post(30, content: const [TextBlock('第一条')]),
        _post(31),
        _post(32),
      ];
      await tester.pumpWidget(
        _app(
          ThreadReplyStrip(
            replies: replies,
            onOpen: (post) => selected = post,
            onOpenAll: () => openedAll++,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('thread-reply-preview-30-0')));
      await tester.pumpAndSettle();
      expect(identical(selected, replies.first), isTrue);
      await tester.tap(find.text('查看已加载的 3 条回复'));
      await tester.pumpAndSettle();
      expect(openedAll, 1);
      await tester.pumpWidget(
        _app(
          ThreadReplyStrip(
            replies: replies,
            showAction: false,
            onOpen: (_) {},
            onOpenAll: () => openedAll++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('查看已加载的'), findsNothing);
      expect(find.byType(PressScale), findsNWidgets(2));
      expect(openedAll, 1);
    },
  );

  testWidgets(
    'reference uses only a matching loaded author and retains its pid for navigation',
    (tester) async {
      const reference = PostReference(
        tid: 50,
        pid: 99,
        url:
            'https://www.chiphell.com/forum.php?mod=redirect&goto=findpost&ptid=50&pid=99',
      );
      int? selectedPid;
      await tester.pumpWidget(
        _app(
          ThreadReplyContext(
            reference: reference,
            target: _post(
              99,
              author: '真实作者',
              content: const [
                QuoteBlock([TextBlock('旧引用')], source: '不可信名字'),
                TextBlock('自己的正文'),
              ],
            ),
            onOpen: () => selectedPid = reference.pid,
          ),
        ),
      );
      expect(find.text('回复 真实作者'), findsOneWidget);
      expect(find.text('自己的正文'), findsOneWidget);
      expect(find.textContaining('不可信名字'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('thread-reply-context-50-99')),
      );
      await tester.pumpAndSettle();
      expect(selectedPid, 99);
    },
  );

  testWidgets(
    'unloaded and mismatched targets never imply deletion or guess an author',
    (tester) async {
      const reference = PostReference(
        tid: 50,
        pid: 99,
        url: 'https://www.chiphell.com/thread-50-1-1.html#pid99',
      );
      for (final target in [null, _post(1, author: '错误作者')]) {
        await tester.pumpWidget(
          _app(
            ThreadReplyContext(
              reference: reference,
              target: target,
              onOpen: () {},
            ),
          ),
        );
        expect(find.text('查看引用楼层'), findsOneWidget);
        expect(find.textContaining('错误作者'), findsNothing);
        expect(find.textContaining('删除'), findsNothing);
      }
    },
  );

  testWidgets(
    '320 dark at 1.8 type retains 44px controls and bounded previews',
    (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final long = List.filled(100, '这里是一段很长的回复。').join();
      final target = _post(
        7,
        author: '需要保持可读的长作者名字',
        content: [TextBlock(long)],
      );
      await tester.pumpWidget(
        _app(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ThreadCommentHeading(
                loadedCount: 120,
                complete: false,
                mode: ThreadViewMode.threaded,
                onModeChanged: (_) {},
              ),
              const SizedBox(height: 16),
              ThreadReplyStrip(
                replies: [
                  target,
                  _post(8, content: [TextBlock(long)]),
                ],
                onOpen: (_) {},
                onOpenAll: () {},
              ),
              const SizedBox(height: 16),
              ThreadReplyContext(
                reference: const PostReference(
                  tid: 50,
                  pid: 7,
                  url: 'https://www.chiphell.com/thread-50-1-1.html#pid7',
                ),
                target: target,
                onOpen: () {},
              ),
            ],
          ),
          large: true,
        ),
      );
      await tester.pumpAndSettle();
      for (final element in find.byType(PressScale).evaluate()) {
        final box = element.findRenderObject()! as RenderBox;
        expect(box.size.height, greaterThanOrEqualTo(44));
        expect(box.size.width, greaterThanOrEqualTo(44));
      }
      final rich = tester.widget<Text>(
        find.byKey(const ValueKey('thread-reply-summary-7-0')),
      );
      expect(rich.maxLines, 2);
      expect(tester.takeException(), isNull);
    },
  );
}
