import 'dart:async';

import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/widgets/article_reply_sheet.dart';
import 'package:chh_app/widgets/composer_sheet.dart';
import 'package:chh_app/widgets/expressive_composer.dart';
import 'package:chh_app/design/icons.dart';
import 'package:chh_app/ui/quote.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smooth_sheets/smooth_sheets.dart';

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
                    quoteAuthor: quote == null ? null : '读者甲',
                    quoteText: quote,
                    onLogin: login,
                  )
                : ComposerSheet.show(
                    context,
                    onSubmit: onSubmit,
                    draftKey: draftKey,
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
      // 引用整块可点,展开文字随内容溢出出现
      final expand = find.text('展开引用');
      expect(expand, findsOneWidget);
      expect(
        tester.getSize(find.byType(QuoteView)).height,
        greaterThanOrEqualTo(44),
      );
      await tester.tap(expand);
      await tester.pumpAndSettle();
      expect(find.text('收起引用'), findsOneWidget);
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
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.complete(const PostResult(PostResultKind.success, 'ok'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byIcon(AppIcons.success), findsOneWidget);
    expect(haptics, contains('HapticFeedbackType.lightImpact'));
    await tester.pumpAndSettle();
    expect(find.byType(ComposerSheet), findsNothing);
  });
}
