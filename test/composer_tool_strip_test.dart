import 'dart:ui' show SemanticsAction;

import 'package:chh_app/design/composer_tokens.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/ui/app_button.dart';
import 'package:chh_app/widgets/composer/composer_tool_strip.dart';
import 'package:chh_app/widgets/composer/voice_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _leadingKey = ValueKey('leading');
const _imageKey = ValueKey('image');
const _sendKey = ValueKey('send');

Widget _app({
  double width = 390,
  double scale = 1,
  bool voice = false,
  bool image = false,
  bool leading = false,
  String label = '发送',
  AppButtonState state = AppButtonState.idle,
  VoidCallback? send,
  Brightness brightness = Brightness.light,
  AppearanceStyle appearance = AppearanceStyle.cinnabar,
}) => MaterialApp(
  theme: buildAppTheme(brightness, appearance),
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: width,
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: ComposerToolStrip(
            voice: voice ? const VoiceCapsule() : null,
            leading: leading
                ? const SizedBox(key: _leadingKey, width: 24, height: 44)
                : null,
            image: image
                ? ComposerImageTool(key: _imageKey, onPressed: () {})
                : null,
            send: AppButton(
              key: _sendKey,
              label: label,
              variant: AppButtonVariant.composerSend,
              state: state,
              onPressed: send,
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('voice stays centered with unequal sides and has no action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final voice = find.bySemanticsLabel('语音输入');
    final strip = find.byType(ComposerToolStrip);
    await tester.pumpWidget(_app(voice: true, image: true));
    final rect = tester.getRect(voice);
    expect(rect.size, const Size(124, 36));
    expect(rect.center, tester.getCenter(strip));
    expect(
      rect.right,
      lessThanOrEqualTo(tester.getTopLeft(find.byKey(_imageKey)).dx),
    );
    expect(
      tester
          .getSemantics(voice)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isFalse,
    );

    await tester.pumpWidget(_app(voice: true, leading: true));
    expect(tester.getRect(voice), rect);
    expect(tester.getRect(find.byKey(_leadingKey)).right, lessThan(rect.left));

    final sendRect = tester.getRect(find.byKey(_sendKey));
    final leadingRect = tester.getRect(find.byKey(_leadingKey));
    await tester.pumpWidget(_app(leading: true));
    expect(voice, findsNothing);
    expect(find.text('按住说话'), findsNothing);
    expect(tester.getRect(find.byKey(_sendKey)), sendRect);
    expect(tester.getRect(find.byKey(_leadingKey)), leadingRect);
    semantics.dispose();
  });

  testWidgets('send capsule follows the label width and stays right aligned', (
    tester,
  ) async {
    final strip = find.byType(ComposerToolStrip);
    final surface = find.byKey(AppButton.surfaceKey);
    final send = find.byKey(_sendKey);
    final image = find.byKey(_imageKey);
    await tester.pumpWidget(_app(voice: true, image: true));
    final pill = tester.getRect(surface);
    expect(pill.width, 60);
    expect(pill.right, tester.getRect(strip).right - ComposerTokens.stripInset);
    expect(pill.height, ComposerTokens.sendHeight);
    expect(tester.getSize(send).height, ComposerTokens.tool);

    for (final (label, state, width) in [
      ('发送', AppButtonState.idle, 60),
      ('发送中', AppButtonState.busy, 75),
      ('已发送', AppButtonState.success, 75),
      ('重试发送', AppButtonState.idle, 90),
    ]) {
      await tester.pumpWidget(
        _app(voice: true, image: true, label: label, state: state, send: () {}),
      );
      await tester.pump();
      final current = tester.getRect(surface);
      expect(current.right, pill.right);
      expect(current.width, width);
      expect(
        tester.getRect(image).right,
        current.left - ComposerTokens.rightGap,
      );
    }
  });

  for (final (width, capsuleWidth) in [(320.0, 88.0), (280.0, 80.0)]) {
    testWidgets('voice and tools fit at ${width}px with large type', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(width: width, scale: 2, voice: true, image: true),
      );
      final voice = tester.getRect(find.bySemanticsLabel('语音输入'));
      final image = tester.getRect(find.byKey(_imageKey));
      final send = tester.getRect(find.byKey(_sendKey));
      expect(voice.width, capsuleWidth);
      expect(voice.center, tester.getCenter(find.byType(ComposerToolStrip)));
      expect(voice.right, lessThanOrEqualTo(image.left));
      expect(image.right, lessThanOrEqualTo(send.left));
      expect(image.width, ComposerTokens.tool);
      expect(send.width, greaterThanOrEqualTo(ComposerTokens.tool));

      await tester.pumpWidget(_app(width: width, scale: 2, image: true));
      expect(find.bySemanticsLabel('语音输入'), findsNothing);
      expect(tester.getRect(find.byKey(_imageKey)), image);
      expect(tester.getRect(find.byKey(_sendKey)), send);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }

  for (final appearance in AppearanceStyle.values) {
    for (final brightness in Brightness.values) {
      testWidgets('send colors in ${appearance.name} ${brightness.name}', (
        tester,
      ) async {
        final tokens = tokensFor(brightness, appearance);
        BoxDecoration decoration() =>
            tester
                    .widget<DecoratedBox>(find.byKey(AppButton.surfaceKey))
                    .decoration
                as BoxDecoration;
        Color? foreground() =>
            tester.widget<Text>(find.text('发送')).style?.color;

        await tester.pumpWidget(
          _app(appearance: appearance, brightness: brightness),
        );
        expect(decoration().color, tokens.fill);
        expect(decoration().gradient, isNull);
        expect(foreground(), tokens.text3);

        await tester.pumpWidget(
          _app(appearance: appearance, brightness: brightness, send: () {}),
        );
        expect(
          decoration().gradient,
          appearance == AppearanceStyle.cinnabar ? tokens.btnGradient : null,
        );
        expect(
          decoration().color,
          appearance == AppearanceStyle.misty ? tokens.accent : null,
        );
        expect(foreground(), tokens.onAccent);
      });
    }
  }
}
