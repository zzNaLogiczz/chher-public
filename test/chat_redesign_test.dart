import 'dart:async';

import 'package:chh_app/design/chat_tokens.dart';
import 'package:chh_app/design/composer_tokens.dart';
import 'package:chh_app/design/motion.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/pm_thread_page.dart';
import 'package:chh_app/ui/app_button.dart';
import 'package:chh_app/ui/chat.dart';
import 'package:chh_app/widgets/composer/composer_tool_strip.dart';
import 'package:chh_app/widgets/avatar_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'messages_ui_test.dart'
    show FakeMessages, showPm, phone, pmFixture, pullPmToRefresh;

PmMessage message(String time, {bool mine = false}) => PmMessage(
  author: mine ? '您' : '对方',
  text: time,
  timeRaw: time,
  fromSelf: mine,
);

class _GroupedMessages extends FakeMessages {
  @override
  Future<List<PmMessage>> conversation(
    String viewUrl, {
    bool refresh = true,
  }) async => [
    message('2026-11-15 10:00'),
    message('2026-11-15 10:10'),
    message('2026-11-15 10:21'),
    message('2026-11-15 10:22', mine: true),
  ];
}

class _ReconcilingMessages extends FakeMessages {
  List<PmMessage> server = [];
  @override
  Future<List<PmMessage>> conversation(
    String viewUrl, {
    bool refresh = true,
  }) async {
    reads++;
    return server;
  }
}

class _PendingMessages extends FakeMessages {
  final result = Completer<List<PmMessage>>();

  @override
  Future<List<PmMessage>> conversation(String viewUrl, {bool refresh = true}) =>
      result.future;
}

void main() {
  test('timestamps require a known gap strictly greater than ten minutes', () {
    final first = message('2026-11-15 10:00');
    expect(chatShowsTimestamp(first, null), isTrue);
    expect(chatShowsTimestamp(message('2026-11-15 10:10'), first), isFalse);
    expect(chatShowsTimestamp(message('2026-11-15 10:11'), first), isTrue);
    expect(chatShowsTimestamp(message(''), first), isFalse);
    expect(chatShowsTimestamp(message('未知'), first), isFalse);
    expect(chatShowsTimestamp(first, message('2026-11-15 10:30')), isFalse);
  });

  testWidgets(
    'adjacent messages join corners and only group tails show avatars',
    (tester) async {
      phone(tester);
      await showPm(tester, _GroupedMessages());
      final bubbles = tester
          .widgetList<ChatBubble>(find.byType(ChatBubble))
          .toList();
      expect(bubbles.length, 4);
      expect(bubbles[0].joinsNext, isTrue);
      expect(bubbles[1].joinsPrevious, isTrue);
      expect(bubbles[1].joinsNext, isFalse);
      expect(bubbles[2].joinsPrevious, isFalse);
      expect(
        find.byKey(const ValueKey('pm-time-2026-11-15 10:00')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('pm-time-2026-11-15 10:10')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('pm-time-2026-11-15 10:21')),
        findsOneWidget,
      );
      expect(
        tester
            .widgetList<AvatarImage>(find.byType(AvatarImage))
            .where((a) => a.size == ChatTokens.avatar)
            .length,
        2,
      );
      expect(find.text('对方'), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets('slow initial conversation still opens at the latest message', (
    tester,
  ) async {
    phone(tester);
    final repo = _PendingMessages();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: PmThreadPage(conversation: pmFixture, repository: repo),
      ),
    );
    await tester.pump(AppMotion.loadingDelay);
    await tester.pump(AppMotion.loadingIn);
    repo.result.complete([
      for (var i = 0; i < 24; i++)
        PmMessage(
          pmid: '$i',
          author: '对方',
          text: '本地私信 $i',
          timeRaw: '2026-11-15 10:10',
        ),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('本地私信 23').hitTestable(), findsOneWidget);
    final list = tester.widget<ListView>(find.byType(ListView));
    expect(list.controller!.offset, greaterThan(100));
  });

  testWidgets('composer growth and keyboard insets resize the message list', (
    tester,
  ) async {
    phone(tester);
    tester.view.viewPadding = const FakeViewPadding(bottom: 18);
    tester.view.padding = tester.view.viewPadding;
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewInsets);
    final repo = _ReconcilingMessages()
      ..server = [
        for (var i = 0; i < 30; i++)
          PmMessage(
            pmid: '$i',
            author: '对方',
            text: '本地私信 $i',
            timeRaw: '2026-11-15 10:10',
          ),
      ];
    await showPm(tester, repo);
    final panel = find.byKey(const ValueKey('pm-composer'));
    final field = find.byKey(const ValueKey('pm-input'));
    final strip = find.byType(ComposerToolStrip);
    final list = find.byType(ListView);
    final latest = find.text('本地私信 29');
    final position = tester.widget<ListView>(list).controller!.position;
    final docked = tester.getRect(panel);
    final editor = tester.getRect(field);
    final toolbar = tester.getRect(strip);
    expect(docked, const Rect.fromLTRB(0, 724, 390, 844));
    expect(editor, const Rect.fromLTRB(20, 730, 376, 774));
    expect(toolbar, const Rect.fromLTRB(0, 774, 390, 826));
    expect(toolbar.height, ComposerTokens.strip);
    expect(tester.getRect(list).bottom, docked.top);
    expect(tester.widget<TextField>(field).style!.fontSize, 15.5);
    expect(tester.widget<TextField>(field).style!.height, 1.5);
    expect(find.text('回复 对方'), findsOneWidget);
    expect(find.text('按住说话'), findsNothing);
    expect(latest.hitTestable(), findsOneWidget);
    final latestGap = docked.top - tester.getBottomRight(latest).dy;

    await tester.showKeyboard(field);
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    tester.view.padding = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    expect(tester.getRect(panel).bottom, 844 - 280);
    expect(tester.getRect(panel).height, 102);
    expect(tester.getRect(list).bottom, tester.getRect(panel).top);

    await tester.enterText(field, '第一行\n第二行');
    await tester.pumpAndSettle();
    expect(tester.getSize(field).height, closeTo(67, 1));
    expect(tester.getRect(list).bottom, tester.getRect(panel).top);
    await tester.enterText(field, List.filled(5, '一行私信').join('\n'));
    await tester.pumpAndSettle();
    final grown = tester.getRect(panel);
    expect(tester.getSize(field).height, closeTo(136.25, 2));
    expect(grown.bottom, 844 - 280);
    expect(tester.getRect(list).bottom, grown.top);
    expect(position.pixels, closeTo(position.maxScrollExtent, .5));
    expect(
      grown.top - tester.getBottomRight(latest).dy,
      closeTo(latestGap, .5),
    );

    await tester.enterText(field, List.filled(8, '一行私信').join('\n'));
    await tester.pumpAndSettle();
    expect(tester.getRect(panel), grown);
    await tester.enterText(field, '');
    FocusManager.instance.primaryFocus?.unfocus();
    tester.view.viewInsets = FakeViewPadding.zero;
    tester.view.padding = tester.view.viewPadding;
    await tester.pumpAndSettle();
    expect(tester.getRect(panel), docked);
    expect(tester.getRect(list).bottom, docked.top);
    expect(position.pixels, closeTo(position.maxScrollExtent, .5));
    expect(repo.sends, 0);
  });

  testWidgets('failed bubble retries once and retains the original draft', (
    tester,
  ) async {
    phone(tester);
    final repo = FakeMessages();
    await showPm(tester, repo);
    await tester.enterText(find.byKey(const ValueKey('pm-input')), '失败样例');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pm-send')));
    await tester.pumpAndSettle();
    expect(find.text('失败样例'), findsNWidgets(2));
    repo.pending = Completer<PostResult>();
    await tester.tap(find.text('未送达，轻点重试'));
    await tester.pump();
    expect(repo.sends, 2);
    repo.pending!.complete(const PostResult(PostResultKind.failed, '失败'));
    await tester.pumpAndSettle();
    expect(find.text('失败样例'), findsNWidgets(2));
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('pm-input')))
          .controller!
          .text,
      '失败样例',
    );
  });

  testWidgets('unknown outcome requires reconciliation before another send', (
    tester,
  ) async {
    final repo = FakeMessages()
      ..response = const PostResult(PostResultKind.unknown, 'unknown');
    await showPm(tester, repo);
    await tester.enterText(find.byKey(const ValueKey('pm-input')), '未知样例');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pm-send')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pm-send')));
    await tester.pumpAndSettle();
    expect(repo.sends, 1);
    expect(find.text('刷新'), findsOneWidget);
  });

  testWidgets(
    'reconciled unknown send preserves a changed draft and unlocks send',
    (tester) async {
      final repo = _ReconcilingMessages()
        ..response = const PostResult(PostResultKind.unknown, 'unknown');
      await showPm(tester, repo);
      final input = find.byKey(const ValueKey('pm-input'));
      await tester.enterText(input, '原来的消息');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pm-send')));
      await tester.pumpAndSettle();
      await tester.enterText(input, '新草稿');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AppButton>(find.byKey(const ValueKey('pm-send')))
            .onPressed,
        isNull,
      );
      repo.server = const [
        PmMessage(
          pmid: 'confirmed',
          author: '您',
          fromSelf: true,
          text: '原来的消息',
          timeRaw: '2026-11-15 10:30',
        ),
      ];
      await pullPmToRefresh(tester);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).controller!.text, '新草稿');
      expect(find.text('原来的消息'), findsOneWidget);
      expect(
        tester
            .widget<AppButton>(find.byKey(const ValueKey('pm-send')))
            .onPressed,
        isNotNull,
      );
      repo.response = const PostResult(PostResultKind.failed, '失败');
      await tester.tap(find.byKey(const ValueKey('pm-send')));
      await tester.pumpAndSettle();
      expect(repo.sends, 2);
      expect(tester.widget<TextField>(input).controller!.text, '新草稿');
    },
  );

  testWidgets('unparsed public response offers refresh without claiming empty', (
    tester,
  ) async {
    final repo = _ReconcilingMessages();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: PmThreadPage(
          repository: repo,
          conversation: const PmConversation(
            id: 'public',
            peer: '系统公告',
            preview: '真实列表预览',
            timeRaw: '',
            viewUrl:
                'https://www.chiphell.com/home.php?mod=space&do=pm&subop=viewg&pmid=1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('暂时无法显示公共消息'), findsOneWidget);
    expect(find.text('这里还没有消息'), findsNothing);
    expect(find.text('公共消息不能回复'), findsOneWidget);
    expect(find.byKey(const ValueKey('pm-input')), findsNothing);
    expect(find.byKey(const ValueKey('pm-send')), findsNothing);
    await tester.tap(find.text('刷新'));
    await tester.pumpAndSettle();
    expect(repo.reads, 2);
    expect(repo.sends, 0);
  });

  testWidgets('reduced motion keeps copied bubble at its original scale', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const Scaffold(
          body: Center(child: ChatBubble(text: '静态复制', mine: false)),
        ),
      ),
    );
    final hold = await tester.startGesture(
      tester.getCenter(find.byType(ChatBubble)),
    );
    await tester.pump(const Duration(milliseconds: 401));
    await hold.up();
    await tester.pumpAndSettle();
    expect(find.text('静态复制'), findsNWidgets(2));
    final transforms = tester.widgetList<Transform>(find.byType(Transform));
    expect(
      transforms.any(
        (t) => (t.transform.storage[0] - ChatTokens.heldScale).abs() < .001,
      ),
      isFalse,
    );
    expect(tester.binding.transientCallbackCount, 0);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('复制'), findsNothing);
  });

  for (final style in AppearanceStyle.values) {
    for (final brightness in Brightness.values) {
      testWidgets('chat retains card contrast in $style $brightness', (
        tester,
      ) async {
        phone(tester);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(brightness, style),
            home: PmThreadPage(
              repository: _GroupedMessages(),
              conversation: const PmConversation(
                id: 'contrast',
                peer: '对方',
                preview: '',
                timeRaw: '',
                viewUrl:
                    'https://www.chiphell.com/home.php?mod=space&do=pm&subop=view&touid=2',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final tokens = tokensFor(brightness, style);
        expect(
          tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
          tokens.grouped,
        );
        for (final bubble in tester.widgetList<ChatBubble>(
          find.byType(ChatBubble),
        )) {
          final bubbleFinder = find.byWidget(bubble);
          final foreground = tester
              .widget<Text>(
                find.descendant(of: bubbleFinder, matching: find.byType(Text)),
              )
              .style!
              .color!;
          final background =
              (tester
                          .widget<DecoratedBox>(
                            find.descendant(
                              of: bubbleFinder,
                              matching: find.byType(DecoratedBox),
                            ),
                          )
                          .decoration
                      as BoxDecoration)
                  .color!;
          final a = foreground.computeLuminance();
          final b = background.computeLuminance();
          final contrast = a > b
              ? (a + .05) / (b + .05)
              : (b + .05) / (a + .05);
          expect(contrast, greaterThanOrEqualTo(4.5));
        }
        await tester.enterText(find.byKey(const ValueKey('pm-input')), '不发送');
        await tester.pumpAndSettle();
        final send = find.byKey(const ValueKey('pm-send'));
        final label = tester.widget<Text>(
          find.descendant(of: send, matching: find.text('发送')),
        );
        final surface =
            tester
                    .widget<DecoratedBox>(
                      find.descendant(
                        of: send,
                        matching: find.byKey(AppButton.surfaceKey),
                      ),
                    )
                    .decoration
                as BoxDecoration;
        final foreground = label.style!.color!;
        final backgrounds =
            (surface.gradient as LinearGradient?)?.colors ?? [surface.color!];
        expect(foreground, tokens.onAccent);
        for (final background in backgrounds) {
          final a = foreground.computeLuminance();
          final b = background.computeLuminance();
          expect(
            a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05),
            greaterThanOrEqualTo(4.5),
          );
        }
        await tester.enterText(find.byKey(const ValueKey('pm-input')), '');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);
      });

      testWidgets('400ms hold copies via one overlay in $style $brightness', (
        tester,
      ) async {
        String? clipboard;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              clipboard = (call.arguments as Map)['text'] as String;
            }
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
          MaterialApp(
            theme: buildAppTheme(brightness, style),
            home: const Scaffold(
              body: Center(child: ChatBubble(text: '本地复制样例', mine: false)),
            ),
          ),
        );
        final hold = await tester.startGesture(
          tester.getCenter(find.byType(ChatBubble)),
        );
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text('复制'), findsNothing);
        await tester.pump(const Duration(milliseconds: 201));
        await hold.up();
        await tester.pumpAndSettle();
        expect(find.text('复制'), findsOneWidget);
        final heldTransform = tester.widget<Transform>(
          find
              .descendant(
                of: find.byType(ChatBubble),
                matching: find.byType(Transform),
              )
              .first,
        );
        expect(
          heldTransform.transform.storage[0],
          closeTo(ChatTokens.heldScale, .00001),
        );
        expect(find.text('本地复制样例'), findsNWidgets(2));
        await tester.tap(find.text('复制'));
        await tester.pump();
        expect(clipboard, '本地复制样例');
        expect(find.text('已复制'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 1400));
        await tester.pumpAndSettle();
        expect(find.text('已复制'), findsNothing);
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('moving before hold cancels copy and reduced motion stays idle', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: Center(child: ChatBubble(text: '取消', mine: true)),
          ),
        ),
      ),
    );
    final hold = await tester.startGesture(
      tester.getCenter(find.byType(ChatBubble)),
    );
    await hold.moveBy(const Offset(40, 0));
    await tester.pump(const Duration(milliseconds: 500));
    await hold.up();
    await tester.pumpAndSettle();
    expect(find.text('复制'), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
  });
}
