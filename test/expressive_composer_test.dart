import 'dart:async';

import 'package:chh_app/design/theme.dart';
import 'package:chh_app/voice/speech_engine.dart';
import 'package:chh_app/widgets/composer/voice_bar.dart';
import 'package:chh_app/design/composer_tokens.dart';
import 'package:chh_app/widgets/composer/composer_panel.dart';
import 'package:chh_app/widgets/composer/composer_tool_strip.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/widgets/article_reply_sheet.dart';
import 'package:chh_app/widgets/composer_sheet.dart';
import 'package:chh_app/widgets/expressive_composer.dart';
import 'package:chh_app/design/icons.dart';
import 'package:chh_app/ui/quote.dart';
import 'package:chh_app/widgets/chhers_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smooth_sheets/smooth_sheets.dart';

import 'support/composer_voice_fixture.dart';

Future<void> _open(
  WidgetTester tester, {
  Future<PostResult> Function(String)? submit,
  double textScale = 1,
  String? draftKey,
  String? quote,
  Future<void> Function()? login,
  bool article = false,
  bool reducedMotion = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetViewInsets);
  final onSubmit =
      submit ?? (_) async => const PostResult(PostResultKind.failed, '离线测试');
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reducedMotion,
        ),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => article
                ? ArticleReplySheet.show(
                    context,
                    onSubmit: onSubmit,
                    articleTitle: '文章标题',
                    quoteAuthor: quote == null ? null : '读者甲',
                    quoteText: quote,
                    onLogin: login,
                  )
                : ComposerSheet.show(
                    context,
                    onSubmit: onSubmit,
                    draftKey: draftKey,
                    threadTitle: '帖子标题',
                    quoteOf: quote == null ? null : '读者甲',
                    quoteText: quote,
                  ),
            child: const Text('打开写作画布'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开写作画布'));
  await tester.pumpAndSettle();
}

Finder get _handle => find.byKey(const ValueKey('composer-drag-handle'));
Finder get _send => find.byKey(const ValueKey('composer-send'));

void main() {
  composerRedesignTests();
  testWidgets('voice service failure keeps speech visible and words undoable', (
    tester,
  ) async {
    final engine = installVoiceFixture();
    await _open(tester);
    await tester.tap(find.byType(VoiceBar));
    await tester.pump();
    engine.emitText(const SpeechText(finalized: '保留文字', interim: ''));
    engine.emitError(SpeechErrorKind.service);
    await tester.pumpAndSettle();
    expect(find.byType(VoiceBar), findsOneWidget);
    expect(find.text('语音识别暂不可用'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '保留文字',
    );
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开写作画布'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(VoiceBar), findsOneWidget);
    expect(find.text('语音识别暂不可用'), findsNothing);
  });
  testWidgets('reply heading uses the square reply arrow', (tester) async {
    await _open(tester, quote: '引用');
    final icon = tester.widget<Icon>(find.byIcon(AppIcons.reply));
    expect(icon.size, 18);
    expect(
      icon.color,
      AppTokens.of(tester.element(find.byType(ComposerPanel))).text3,
    );
  });
  for (final sending in [false, true]) {
    testWidgets('IME back closes composer once, busy=$sending', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const channel = MethodChannel('chh/composer_back');
      final enabled = <bool>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        enabled.add(call.arguments as bool);
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final pending = Completer<PostResult>();
      await _open(
        tester,
        draftKey: 'ime-back-$sending',
        submit: (_) => pending.future,
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 310);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('composer-canvas')),
        '保留草稿',
      );
      await tester.pumpAndSettle();
      expect(enabled.last, isTrue);
      if (!sending) {
        final navigator = Navigator.of(
          tester.element(find.byType(ExpressiveComposer)),
        );
        unawaited(
          navigator.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('验证页面')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(enabled.last, isFalse);
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'chh/composer_back',
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('back'),
          ),
          (_) {},
        );
        await tester.pumpAndSettle();
        expect(find.text('验证页面'), findsOneWidget);
        navigator.pop();
        await tester.pumpAndSettle();
        expect(enabled.last, isTrue);
      }
      if (sending) {
        await tester.tap(_send);
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump();
        expect(
          tester
              .widget<PopScope<PostResult>>(find.byType(PopScope<PostResult>))
              .canPop,
          isFalse,
        );
      }
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'chh/composer_back',
        const StandardMethodCodec().encodeMethodCall(const MethodCall('back')),
        (_) {},
      );
      if (sending) {
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byType(ExpressiveComposer), findsOneWidget);
        expect(find.text('保留草稿'), findsOneWidget);
        pending.complete(const PostResult(PostResultKind.failed, '离线测试'));
        await tester.pump();
        await tester.pumpAndSettle();
        await tester.tap(find.text('取消'));
      }
      await tester.pumpAndSettle();
      expect(find.byType(ExpressiveComposer), findsNothing);
      expect(enabled.last, isFalse);
      tester.view.resetViewInsets();
      await tester.tap(find.text('打开写作画布'));
      await tester.pumpAndSettle();
      expect(find.text('保留草稿'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('disposing an outgoing reply keeps the next IME back active', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const channel = MethodChannel('chh/composer_back');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await _open(tester, quote: '引用');
    tester.view.viewInsets = const FakeViewPadding(bottom: 310);
    await tester.pumpAndSettle();
    final open = tester
        .widget<TextButton>(find.widgetWithText(TextButton, '打开写作画布'))
        .onPressed!;
    final old = tester.state(find.byType(ExpressiveComposer));
    final navigator = Navigator.of(old.context);

    await navigator.maybePop();
    await tester.pump();
    open();
    await tester.pump();
    expect(old.mounted, isTrue);
    await tester.pumpAndSettle();
    expect(old.mounted, isFalse);
    expect(find.byType(ExpressiveComposer), findsOneWidget);

    await messenger.handlePlatformMessage(
      'chh/composer_back',
      const StandardMethodCodec().encodeMethodCall(const MethodCall('back')),
      (_) {},
    );
    await tester.pumpAndSettle();
    expect(find.byType(ExpressiveComposer), findsNothing);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('composer cancel uses secondary text, not accent', (
    tester,
  ) async {
    await _open(tester);
    expect(
      tester.widget<Text>(find.text('取消')).style!.color,
      AppTokens.light.text2,
    );
  });
  testWidgets(
    'reduced motion quote expansion does not animate its own layout',
    (tester) async {
      await _open(
        tester,
        article: true,
        reducedMotion: true,
        quote: List.filled(20, '这是一段需要折叠的引用内容。').join('\n'),
      );
      await tester.tap(find.byKey(const ValueKey('composer-context')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('展开'));
      await tester.pumpAndSettle();
      expect(find.text('收起'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '保留输入内容');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'real smooth sheet expands, tracks a cancelled drag and keeps the draft',
    (tester) async {
      await _open(tester);
      expect(find.byType(Sheet), findsOneWidget);
      final halfTop = tester.getTopLeft(_handle).dy;
      expect(halfTop, greaterThan(100));
      await tester.enterText(find.byType(TextField), '拖动中保留的内容');
      // 全屏按钮已去掉:拖动顶部拖动条展开
      await tester.drag(_handle, const Offset(0, -400));
      await tester.pumpAndSettle();
      final fullTop = tester.getTopLeft(_handle).dy;
      expect(fullTop, lessThan(halfTop - 100));
      final drag = await tester.startGesture(tester.getCenter(_handle));
      await drag.moveBy(const Offset(0, 20));
      await drag.moveBy(const Offset(0, 100));
      await tester.pump();
      expect(tester.getTopLeft(_handle).dy, greaterThan(fullTop + 40));
      await drag.cancel();
      await tester.pumpAndSettle();
      expect(find.byType(ComposerSheet), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '拖动中保留的内容',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('drag dismissal stores a keyed draft for the next opening', (
    tester,
  ) async {
    var submissions = 0;
    await _open(
      tester,
      draftKey: 'expressive-drag-draft',
      submit: (_) async {
        submissions++;
        return const PostResult(PostResultKind.success, '');
      },
    );
    await tester.enterText(find.byType(TextField), '收起后继续写');
    await tester.drag(_handle, const Offset(0, 620));
    await tester.pumpAndSettle();
    expect(find.byType(ComposerSheet), findsNothing);
    await tester.tap(find.text('打开写作画布'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '收起后继续写',
    );
    expect(submissions, 0);
  });

  testWidgets(
    'keyboard and large type leave the primary action above the keyboard',
    (tester) async {
      await _open(tester, textScale: 1.8, article: true, quote: '需要保留的引用上下文。');
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '大字号下继续编辑');
      await tester.pumpAndSettle();
      expect(tester.getRect(_send).bottom, lessThanOrEqualTo(544));
      expect(tester.getSize(_send).height, greaterThanOrEqualTo(44));
      expect(
        tester.widget<TextField>(find.byType(TextField)).decoration!.filled,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'sending locks dismissal and confirmed success is visible before closing',
    (tester) async {
      final pending = Completer<PostResult>();
      var submissions = 0;
      await _open(
        tester,
        submit: (_) {
          submissions++;
          return pending.future;
        },
      );
      await tester.enterText(find.byType(TextField), '等待服务器确认的内容');
      await tester.pump();
      await tester.tap(_send);
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('发送中'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
      expect(find.text('已发送'), findsNothing);
      await tester.drag(_handle, const Offset(0, 620));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(ComposerSheet), findsOneWidget);
      expect(submissions, 1);
      pending.complete(const PostResult(PostResultKind.success, 'confirmed'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('已发送'), findsOneWidget);
      expect(find.byIcon(AppIcons.success), findsOneWidget);
      expect(find.byType(ComposerSheet), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.byType(ComposerSheet), findsNothing);
    },
  );

  testWidgets(
    'quoted context expands through a 44px control and login keeps writing intact',
    (tester) async {
      var logins = 0;
      var submissions = 0;
      await _open(
        tester,
        article: true,
        quote: List.filled(8, '引用评论的上下文内容。').join('\n'),
        login: () async {
          logins++;
        },
        submit: (_) async {
          submissions++;
          return const PostResult(PostResultKind.loginRequired, '');
        },
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('composer-context')))
            .maxLines,
        1,
      );
      await tester.tap(find.byKey(const ValueKey('composer-context')));
      await tester.pumpAndSettle();
      // 四行后通过展开按钮继续阅读
      final expand = find.text('展开');
      expect(expand, findsOneWidget);
      expect(
        tester.getSize(find.byType(QuoteView)).height,
        greaterThanOrEqualTo(44),
      );
      await tester.tap(expand);
      await tester.pumpAndSettle();
      expect(find.text('收起'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '登录后继续的草稿');
      await tester.pump();
      await tester.tap(_send);
      await tester.pumpAndSettle();
      await tester.tap(find.text('登录'));
      await tester.pumpAndSettle();
      expect(logins, 1);
      expect(submissions, 1);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '登录后继续的草稿',
      );
    },
  );

  testWidgets('typing does not rebuild the whole sheet header each character', (
    tester,
  ) async {
    await _open(tester);
    final title = tester.widget<Text>(find.text('写回复'));
    await tester.enterText(find.byType(TextField), '输入一段内容');
    await tester.pump();
    expect(tester.widget<Text>(find.text('写回复')), same(title));
    expect(find.byType(ExpressiveComposer), findsOneWidget);
  });
}

void composerRedesignTests() {
  for (final article in [false, true]) {
    final hostName = article ? 'article comment' : 'reply';
    hostDictationKeyboardTests(hostName, (tester) async {
      await _open(tester, article: article);
      return find.byType(TextField);
    });
    testWidgets('dictation inserts and undoes text in $hostName', (
      tester,
    ) async {
      final engine = installVoiceFixture();
      await _open(
        tester,
        article: article,
        submit: (_) async => throw StateError('Unexpected submission'),
      );
      await expectHostDictation(tester, engine, find.byType(TextField));
    });

    testWidgets(
      'docked composer measures content and toggles full height (article=$article)',
      (tester) async {
        tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 18);
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 18);
        addTearDown(tester.view.reset);
        installVoiceFixture();
        await _open(tester, article: article);
        final panel = find.byType(ComposerPanel);
        final toolbar = find.byType(ComposerToolStrip);
        final editor = find.byType(TextField);
        final compact = tester.getRect(panel);
        expect(compact.left, 0);
        expect(compact.right, 390);
        expect(compact.bottom, 844);
        expect(tester.getRect(toolbar).bottom, 844 - 18);
        expect(tester.getSize(toolbar).height, ComposerTokens.strip);
        expect(compact.height - 18, closeTo(245, 0.5));
        expect(tester.widget<TextField>(editor).minLines, 1);
        expect(find.text(article ? '文章标题' : '帖子标题'), findsOneWidget);
        expect(tester.getCenter(find.text('按住说话')).dx, greaterThan(195));

        final sendRect = tester.getRect(_send);
        await tester.tap(_handle);
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(_handle).dy, 24 + 8);
        expect(tester.getRect(_send), sendRect);
        await tester.tap(_handle);
        // The spring only moves the upper panel, including on overshoot.
        for (var frame = 0; frame < 30; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(tester.getRect(_send), sendRect);
        }
        await tester.pumpAndSettle();
        expect(tester.getRect(panel), compact);

        await tester.enterText(editor, '第一行\n第二行');
        await tester.pumpAndSettle();
        expect(tester.getRect(panel), compact);

        await tester.enterText(editor, List.filled(6, '第几行').join('\n'));
        await tester.pumpAndSettle();
        final grown = tester.getRect(panel);
        expect(grown.height - 18, closeTo(344.6, 3));
        expect(grown.bottom, compact.bottom);

        await tester.drag(_handle, const Offset(0, -260));
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(_handle).dy, 24 + 8);
        await tester.drag(_handle, const Offset(0, 400));
        await tester.pumpAndSettle();
        expect(tester.getRect(panel), grown);
        await tester.drag(_handle, const Offset(0, 400));
        await tester.pumpAndSettle();
        expect(panel, findsNothing);
      },
    );
  }

  testWidgets('content fills available height then scrolls inside the editor', (
    tester,
  ) async {
    await _open(tester, article: true);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    final panel = find.byType(ComposerPanel);
    final editor = find.byType(TextField);
    expect(tester.getTopLeft(panel).dy, greaterThan(8));
    expect(tester.getBottomLeft(panel).dy, 544);

    await tester.enterText(editor, List.filled(60, '超长草稿').join('\n'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(panel).dy, 8);
    expect(tester.getBottomLeft(panel).dy, 544);
    final scrollable = find.descendant(
      of: editor,
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(0));
    position.jumpTo(0);
    await tester.drag(editor, const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0));
    expect(tester.getTopLeft(panel).dy, 8);

    await tester.tap(find.text('取消'));
    await tester.pump();
    tester.view.resetViewInsets();
    await tester.pump();
    expect(tester.getBottomLeft(panel).dy, 544);
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.getBottomLeft(panel).dy, lessThan(650));
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
  });

  testWidgets(
    'forum reply has one-line context above the editor and send below',
    (tester) async {
      await _open(tester, quote: '需要回复的正文\n第二行仅保留为一行引用');
      expect(find.text('回复 读者甲'), findsOneWidget);
      expect(find.byType(QuoteView), findsNothing);
      final context = find.text('需要回复的正文\n第二行仅保留为一行引用');
      expect(tester.widget<Text>(context).maxLines, 1);
      expect(
        tester.getBottomLeft(context).dy,
        lessThan(tester.getTopLeft(find.byType(TextField)).dy),
      );
      expect(
        tester.getTopLeft(_send).dy,
        greaterThan(tester.getBottomLeft(find.byType(TextField)).dy),
      );
      expect(find.text('楼层回复'), findsNothing);
      await tester.enterText(find.byType(TextField), '未发送的草稿');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.byType(ComposerSheet), findsNothing);
    },
  );
  testWidgets('a tall failure notice scrolls above the docked send control', (
    tester,
  ) async {
    final message = List.filled(25, '发送失败，请稍后再试。').join('\n');
    await _open(
      tester,
      article: true,
      textScale: 1.8,
      submit: (_) async => PostResult(PostResultKind.failed, message),
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '保留的评论草稿');
    await tester.pump();
    final sendRect = tester.getRect(_send);
    await tester.tap(_send);
    await tester.pumpAndSettle();

    expect(find.text(message), findsOneWidget);
    expect(find.text('重试发送'), findsOneWidget);
    final retryRect = tester.getRect(_send);
    expect(retryRect.right, sendRect.right);
    expect(retryRect.bottom, sendRect.bottom);
    expect(retryRect.width, greaterThan(sendRect.width));
    final notice = find.ancestor(
      of: find.text(message),
      matching: find.byType(SingleChildScrollView),
    );
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: notice, matching: find.byType(Scrollable)),
        )
        .position;
    expect(position.maxScrollExtent, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('send stays visible above the keyboard', (tester) async {
    await _open(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    final send = tester.getRect(find.byKey(const ValueKey('composer-send')));
    expect(send.bottom, lessThan(844 - 300));
    expect(send.top, greaterThanOrEqualTo(0));
  });

  testWidgets('send morphs busy then success and fires a light haptic', (
    tester,
  ) async {
    final haptics = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments);
        }
        return null;
      },
    );
    final pending = Completer<PostResult>();
    var submissions = 0;
    await _open(
      tester,
      submit: (_) {
        submissions++;
        return pending.future;
      },
    );
    await tester.enterText(find.byType(TextField), '确认后再收起');
    await tester.pump();
    await tester.tap(find.text('发送'));
    await tester.pump();
    await tester.tap(find.text('发送中'), warnIfMissed: false);
    await tester.pump();
    expect(submissions, 1);
    final spinner = find.byWidgetPredicate(
      (widget) => widget is ChhersSpinner && widget.active,
    );
    expect(spinner, findsOneWidget);
    expect(
      find.descendant(of: spinner, matching: find.byType(FadeTransition)),
      findsNothing,
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.descendant(of: spinner, matching: find.byType(FadeTransition)),
      findsOneWidget,
    );
    pending.complete(const PostResult(PostResultKind.success, 'ok'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byIcon(AppIcons.success), findsOneWidget);
    expect(haptics, contains('HapticFeedbackType.lightImpact'));
    await tester.pumpAndSettle();
    expect(find.byType(ComposerSheet), findsNothing);
  });
}
