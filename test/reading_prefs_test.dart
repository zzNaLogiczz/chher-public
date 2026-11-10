import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chh_app/core/reading_prefs.dart';
import 'package:chh_app/design/reading.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/article_page.dart';
import 'package:chh_app/pages/thread_detail_page.dart';
import 'package:chh_app/ui/app_button.dart';
import 'package:chh_app/ui/reading_settings_sheet.dart';
import 'package:chh_app/ui/segmented.dart';
import 'package:chh_app/widgets/article_discussion_widgets.dart';
import 'package:chh_app/widgets/rich_content_text.dart';
import 'package:chh_app/widgets/thread_comment_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('reading preferences', () {
    late Directory directory;
    late ReadingPrefsController controller;
    File file() => File('${directory.path}/reading-v1.json');
    setUp(() {
      directory = Directory.systemTemp.createTempSync('chh-reading-');
      controller = ReadingPrefsController(directory: () async => directory);
    });
    tearDown(() {
      controller.dispose();
      directory.deleteSync(recursive: true);
    });

    test('missing file defaults, copyWith and value equality', () async {
      await controller.load();
      expect(controller.prefs, const ReadingPrefs());
      expect(controller.prefs.isDefault, isTrue);
      expect(controller.prefs.copyWith(), controller.prefs);
      expect(controller.prefs.copyWith().hashCode, controller.prefs.hashCode);
      expect(
        controller.prefs.copyWith(layout: ReadingLayout.compact).isDefault,
        isFalse,
      );
    });

    test('notifies immediately, persists atomically and restores', () async {
      const prefs = ReadingPrefs(
        fontSize: ReadingFontSize.xl,
        lineHeight: ReadingLineHeight.loose,
        layout: ReadingLayout.compact,
      );
      final notifications = <ReadingPrefs>[];
      controller.addListener(() => notifications.add(controller.prefs));
      final saving = controller.set(prefs);
      expect(controller.prefs, prefs);
      expect(notifications, [prefs]);
      await saving;
      expect(jsonDecode(await file().readAsString()), {
        'version': 1,
        'fontSize': 'xl',
        'lineHeight': 'loose',
        'layout': 'compact',
        'imagesExpanded': false,
        'commentMode': 'threaded',
      });
      expect(File('${file().path}.tmp').existsSync(), isFalse);
      final restored = ReadingPrefsController(directory: () async => directory);
      addTearDown(restored.dispose);
      await restored.load();
      expect(restored.prefs, prefs);
      await controller.reset();
      expect(controller.prefs.isDefault, isTrue);
      expect(jsonDecode(await file().readAsString()), {
        'version': 1,
        'fontSize': 'm',
        'lineHeight': 'standard',
        'layout': 'comfy',
        'imagesExpanded': false,
        'commentMode': 'threaded',
      });
    });

    for (final payload in [
      '{broken',
      '[]',
      '{"version":2,"fontSize":"xl"}',
      '{"version":1,"fontSize":"unknown","lineHeight":"standard","layout":"comfy"}',
      '{"version":1,"fontSize":"xl","lineHeight":"loose"}',
    ]) {
      test('invalid data falls back to defaults: $payload', () async {
        await file().writeAsString(payload);
        await controller.load();
        expect(controller.prefs.isDefault, isTrue);
      });
    }

    test('rapid updates persist the final selection', () async {
      await Future.wait([
        for (final size in ReadingFontSize.values)
          controller.set(ReadingPrefs(fontSize: size)),
      ]);
      final restored = ReadingPrefsController(directory: () async => directory);
      addTearDown(restored.dispose);
      await restored.load();
      expect(restored.prefs, const ReadingPrefs(fontSize: ReadingFontSize.xl));
    });

    test(
      'late disk read cannot override a new selection, including reset',
      () async {
        await file().writeAsString(
          '{"version":1,"fontSize":"xl","lineHeight":"loose","layout":"compact"}',
        );
        final pending = Completer<Directory?>();
        var calls = 0;
        final delayed = ReadingPrefsController(
          directory: () => calls++ == 0 ? pending.future : Future.value(null),
        );
        addTearDown(delayed.dispose);
        final loading = delayed.load();
        await delayed.reset();
        pending.complete(directory);
        await loading;
        expect(delayed.prefs.isDefault, isTrue);
      },
    );

    test(
      'late disk read still updates preferences after startup timeout',
      () async {
        await file().writeAsString(
          '{"version":1,"fontSize":"xl","lineHeight":"loose","layout":"compact"}',
        );
        final pending = Completer<Directory?>();
        final delayed = ReadingPrefsController(directory: () => pending.future);
        addTearDown(delayed.dispose);
        final loading = delayed.load();
        await loading.timeout(Duration.zero, onTimeout: () {});
        expect(delayed.prefs.isDefault, isTrue);
        pending.complete(directory);
        await loading;
        expect(delayed.prefs.fontSize, ReadingFontSize.xl);
      },
    );

    test('display choices restore and old files retain defaults', () async {
      await controller.set(
        const ReadingPrefs(
          imagesExpanded: true,
          commentMode: CommentViewMode.author,
        ),
      );
      final restored = ReadingPrefsController(directory: () async => directory);
      addTearDown(restored.dispose);
      await restored.load();
      expect(restored.prefs.imagesExpanded, isTrue);
      expect(restored.prefs.commentMode, CommentViewMode.author);
      await file().writeAsString(
        '{"version":1,"fontSize":"xl","lineHeight":"loose","layout":"compact"}',
      );
      final legacy = ReadingPrefsController(directory: () async => directory);
      addTearDown(legacy.dispose);
      await legacy.load();
      expect(legacy.prefs.fontSize, ReadingFontSize.xl);
      expect(legacy.prefs.imagesExpanded, isFalse);
      expect(legacy.prefs.commentMode, CommentViewMode.threaded);
    });

    test('unavailable storage preserves in-memory selection', () async {
      final unavailable = ReadingPrefsController(directory: () async => null);
      addTearDown(unavailable.dispose);
      await unavailable.load();
      await unavailable.set(const ReadingPrefs(fontSize: ReadingFontSize.s));
      expect(unavailable.prefs.fontSize, ReadingFontSize.s);
    });
  });

  test('all metric combinations match the specification and cap scaling', () {
    for (final size in ReadingFontSize.values) {
      for (final height in ReadingLineHeight.values) {
        for (final layout in ReadingLayout.values) {
          final metrics = ReadingMetrics.fromPrefs(
            ReadingPrefs(fontSize: size, lineHeight: height, layout: layout),
          );
          final body = [15.0, 16.0, 17.0, 18.0, 20.0][size.index];
          final line = [1.55, 1.7, 1.85][height.index];
          expect(metrics.bodySize, body);
          expect(metrics.commentSize, body - 1);
          expect(metrics.bodyHeight, line);
          expect(metrics.commentHeight, closeTo(line - .1, .0001));
          expect(
            [
              metrics.gutter,
              metrics.postVPad,
              metrics.avatar,
              metrics.avatarNested,
              metrics.openingAvatar,
              metrics.paragraphGap,
              metrics.titleSize,
              metrics.imageGap,
              metrics.sectionBand,
            ],
            layout == ReadingLayout.comfy
                ? [20, 12, 32, 24, 36, 10, 24, 12, 8]
                : [16, 8, 28, 22, 32, 6, 22, 8, 6],
          );
          expect(
            metrics.textScaler(const TextScaler.linear(2)).scale(body),
            closeTo(26, .0001),
          );
          expect(
            metrics.textScaler(const TextScaler.linear(.8)).scale(body),
            closeTo(body * .8, .0001),
          );
        }
      }
    }
  });

  testWidgets('metrics without a scope fall back to defaults', (tester) async {
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          expect(ReadingMetrics.of(context).bodySize, 17);
          return const SizedBox();
        },
      ),
    );
  });

  group('reading settings UI', () {
    late ReadingPrefsController controller;
    setUp(
      () => controller = ReadingPrefsController(directory: () async => null),
    );
    tearDown(() => controller.dispose());
    Widget app(Widget child, {TextScaler scaler = TextScaler.noScaling}) =>
        ReadingScope(
          controller: controller,
          child: MaterialApp(
            theme: buildAppTheme(Brightness.light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: scaler),
              child: child!,
            ),
            home: child,
          ),
        );

    testWidgets(
      'sheet updates scope, segments and slider; reset is disabled by default',
      (tester) async {
        final haptics = <MethodCall>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            haptics.add(call);
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await tester.pumpWidget(
          app(
            Builder(
              builder: (context) => Scaffold(
                body: Column(
                  children: [
                    Text(
                      '${ReadingMetrics.of(context).bodyHeight}',
                      key: const ValueKey('live-height'),
                    ),
                    TextButton(
                      onPressed: () => showReadingSettingsSheet(context),
                      child: const Text('打开'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('打开'));
        await tester.pumpAndSettle();
        final reset = find.widgetWithText(AppButton, '恢复默认');
        expect(tester.widget<AppButton>(reset).onPressed, isNull);
        await tester.tap(find.text('宽松'));
        await tester.pumpAndSettle();
        expect(controller.prefs.lineHeight, ReadingLineHeight.loose);
        expect(
          tester.widget<Text>(find.byKey(const ValueKey('live-height'))).data,
          '1.85',
        );
        await tester.tap(
          find.descendant(
            of: find.byType(AppSegmented<ReadingLayout>),
            matching: find.text('紧凑'),
          ),
        );
        await tester.pumpAndSettle();
        expect(controller.prefs.layout, ReadingLayout.compact);
        haptics.clear();
        tester.widget<Slider>(find.byType(Slider)).onChanged!(4);
        tester.widget<Slider>(find.byType(Slider)).onChanged!(4);
        await tester.pumpAndSettle();
        expect(controller.prefs.fontSize, ReadingFontSize.xl);
        expect(find.text('最大 · 20'), findsOneWidget);
        expect(
          haptics.where(
            (call) =>
                call.method == 'HapticFeedback.vibrate' &&
                call.arguments == 'HapticFeedbackType.selectionClick',
          ),
          hasLength(1),
        );
        await tester.tap(reset);
        await tester.pumpAndSettle();
        expect(controller.prefs.isDefault, isTrue);
        expect(tester.widget<AppButton>(reset).onPressed, isNull);
      },
    );

    testWidgets('a selection becomes the default for another thread', (
      tester,
    ) async {
      Widget thread(int id, {int? focusPid}) => ThreadDetailPage(
        key: ValueKey(id),
        tid: id,
        title: '示例',
        focusPid: focusPid,
        loadPage: (_, author, _) async => ThreadDetail(
          tid: id,
          title: '示例',
          posts: [
            const Post(
              pid: 1,
              floor: 1,
              author: '楼主',
              authorUid: 'owner',
              timeRaw: '',
              content: [TextBlock('正文')],
            ),
            if (author == null)
              const Post(
                pid: 2,
                floor: 2,
                author: '读者',
                authorUid: 'reader',
                timeRaw: '',
                content: [TextBlock('评论')],
              ),
          ],
          page: const PageInfo(current: 1, hasNext: false),
        ),
      );
      ThreadCommentHeading heading() => tester.widget<ThreadCommentHeading>(
        find.byType(ThreadCommentHeading),
      );
      await tester.pumpWidget(app(thread(101)));
      await tester.pumpAndSettle();
      heading().onModeChanged(ThreadViewMode.floors);
      await tester.pumpAndSettle();
      expect(controller.prefs.commentMode, CommentViewMode.floors);
      await tester.pumpWidget(app(thread(102)));
      await tester.pumpAndSettle();
      expect(heading().mode, ThreadViewMode.floors);
      heading().onModeChanged(ThreadViewMode.author);
      await tester.pumpAndSettle();
      expect(controller.prefs.commentMode, CommentViewMode.author);
      await tester.pumpWidget(app(thread(103)));
      await tester.pumpAndSettle();
      expect(heading().mode, ThreadViewMode.author);
      await tester.pumpWidget(app(thread(104, focusPid: 2)));
      await tester.pumpAndSettle();
      expect(heading().mode, ThreadViewMode.threaded);
      expect(controller.prefs.commentMode, CommentViewMode.author);
      expect(tester.takeException(), isNull);
    });

    for (final userChoosesFirst in [false, true]) {
      testWidgets('late defaults respect prior choice: $userChoosesFirst', (
        tester,
      ) async {
        final directory = Directory.systemTemp.createTempSync('late-reading-');
        addTearDown(() => directory.deleteSync(recursive: true));
        File('${directory.path}/reading-v1.json').writeAsStringSync(
          '{"version":1,"fontSize":"m","lineHeight":"standard","layout":"comfy","commentMode":"author"}',
        );
        final pending = Completer<Directory?>();
        controller.dispose();
        var directoryCalls = 0;
        controller = ReadingPrefsController(
          directory: () =>
              directoryCalls++ == 0 ? pending.future : Future.value(null),
        );
        late Future<void> loading;
        await tester.runAsync(() async {
          loading = controller.load();
        });
        await tester.pumpWidget(
          app(
            ThreadDetailPage(
              tid: 101,
              title: '延迟偏好',
              loadPage: (_, author, _) async => ThreadDetail(
                tid: 101,
                title: '延迟偏好',
                posts: [
                  const Post(
                    pid: 1,
                    floor: 1,
                    author: '楼主',
                    authorUid: 'owner',
                    timeRaw: '',
                    content: [TextBlock('正文')],
                  ),
                  if (author == null)
                    const Post(
                      pid: 2,
                      floor: 2,
                      author: '读者',
                      authorUid: 'reader',
                      timeRaw: '',
                      content: [TextBlock('评论')],
                    ),
                ],
                page: const PageInfo(current: 1, hasNext: false),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        ThreadCommentHeading heading() => tester.widget<ThreadCommentHeading>(
          find.byType(ThreadCommentHeading),
        );
        expect(heading().mode, ThreadViewMode.threaded);
        if (userChoosesFirst) {
          heading().onModeChanged(ThreadViewMode.floors);
          await tester.pumpAndSettle();
        }
        await tester.runAsync(() async {
          pending.complete(directory);
          await loading;
        });
        await tester.pumpAndSettle();
        expect(
          heading().mode,
          userChoosesFirst ? ThreadViewMode.floors : ThreadViewMode.author,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('thread toolbar opens reading settings', (tester) async {
      await tester.pumpWidget(
        app(
          ThreadDetailPage(
            tid: 1,
            title: '示例',
            loadPage: (_, _, _) async => const ThreadDetail(
              tid: 1,
              title: '示例',
              posts: [],
              page: PageInfo(current: 1, hasNext: false),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('thread-reading-settings')),
        findsOneWidget,
      );
      expect(find.byTooltip('查看原页面'), findsOneWidget);
      await tester.tap(find.byTooltip('阅读设置'));
      await tester.pumpAndSettle();
      expect(find.text('帖子页和文章页通用 · 会叠加系统字体大小'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
    });

    testWidgets('article body reacts live and caps system scaling locally', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          ArticlePage(
            aid: 1,
            title: '文章标题',
            loadPage: (_, _) async => const ArticleContent(
              ArticleDetail(
                aid: 1,
                title: '文章标题',
                content: [TextBlock('文章正文')],
                page: PageInfo(current: 1, hasNext: false),
              ),
            ),
          ),
          scaler: const TextScaler.linear(2),
        ),
      );
      await tester.pumpAndSettle();
      final body = find.byType(RichContentText).first;
      expect(tester.widget<RichContentText>(body).style?.fontSize, 17);
      await tester.runAsync(
        () => controller.set(
          const ReadingPrefs(
            fontSize: ReadingFontSize.xl,
            lineHeight: ReadingLineHeight.compact,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final style = tester.widget<RichContentText>(body).style!;
      expect(style.fontSize, 20);
      expect(style.height, 1.55);
      expect(
        MediaQuery.textScalerOf(tester.element(body)).scale(style.fontSize!),
        closeTo(26, .0001),
      );
      expect(
        MediaQuery.textScalerOf(
          tester.element(find.byTooltip('阅读设置')),
        ).scale(20),
        40,
      );
      await tester.tap(find.byTooltip('阅读设置'));
      await tester.pumpAndSettle();
      expect(find.byType(Slider), findsOneWidget);
    });

    testWidgets('article comment body follows preferences', (tester) async {
      await tester.pumpWidget(
        app(
          const Scaffold(
            body: DiscussionCommentContent(blocks: [TextBlock('评论正文')]),
          ),
        ),
      );
      final body = find.byType(RichContentText);
      expect(tester.widget<RichContentText>(body).style?.fontSize, 16);
      await tester.runAsync(
        () => controller.set(
          const ReadingPrefs(
            fontSize: ReadingFontSize.xs,
            lineHeight: ReadingLineHeight.compact,
          ),
        ),
      );
      await tester.pump();
      expect(tester.widget<RichContentText>(body).style?.fontSize, 14);
      expect(
        tester.widget<RichContentText>(body).style?.height,
        closeTo(1.45, .0001),
      );
    });
  });
}
