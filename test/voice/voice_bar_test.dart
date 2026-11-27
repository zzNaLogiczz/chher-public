import 'dart:async';
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:chh_app/design/composer_tokens.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/voice/fake_speech_engine.dart';
import 'package:chh_app/voice/speech_engine.dart';
import 'package:chh_app/widgets/composer/composer_tool_strip.dart';
import 'package:chh_app/widgets/composer/dictation_controller.dart';
import 'package:chh_app/widgets/composer/voice_bar.dart';
import 'package:chh_app/widgets/composer/voice_liquid_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final _voice = find.byType(VoiceBar);

void main() {
  testWidgets('press spreads from the touch before the engine is ready', (
    tester,
  ) async {
    final engine = _DelayedMic();
    final haptics = <Object?>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final rig = await _mount(tester, create: () => engine);
    final touch = tester.getCenter(_voice) - const Offset(32, 0);
    final press = await tester.startGesture(touch);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final liquid = _liquidPainter(tester);
    expect(liquid.motion.frame.origin, -32);
    expect(liquid.motion.frame.spread, allOf(greaterThan(0), lessThan(1)));
    for (var i = 0; i < 32; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(rig.phase, DictationPhase.press);
    expect(find.text('0:00'), findsOneWidget);
    final rect = tester.getRect(_voice);
    expect(
      tester.getTopLeft(find.text('0:00')).dx,
      rect.left + ComposerTokens.voiceLabelInset,
    );
    expect(haptics, ['HapticFeedbackType.lightImpact']);
    engine.ready.complete();
    await tester.pump();
    await press.up();
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pump(const Duration(milliseconds: 2400));
  });

  testWidgets('reduced motion fades and animates only capacity until release', (
    tester,
  ) async {
    final rig = await _mount(tester, reducedMotion: true);
    final press = await tester.startGesture(tester.getCenter(_voice));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final painter = _liquidPainter(tester);
    expect(painter.motion.frame.spread, 1);
    expect(painter.motion.frame.opacity, 1);
    expect(painter.motion.needsTick, isFalse);
    // Flutter's AnimatedOpacity retires its side-tool ticker on the next
    // tick after the exact endpoint, where the opacity is already zero.
    await tester.pump(const Duration(milliseconds: 1));
    expect(tester.binding.transientCallbackCount, 1);
    final startWidth = _capacityPaint(painter)!.rect.width;
    rig.engine.emitVolume(1);
    await tester.pump(const Duration(seconds: 1));
    expect(painter.motion.frame.time, 0);
    expect(painter.motion.frame.flow, 0);
    expect(painter.motion.ripples, isEmpty);
    expect(tester.binding.transientCallbackCount, 1);
    expect(_capacityPaint(painter)!.rect.width, greaterThan(startWidth));
    await press.up();
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    expect(find.text('按住说话'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2400));
  });

  testWidgets(
    'a short press starts immediately and a tap anywhere ends hands-free',
    (tester) async {
      final rig = await _mount(tester);
      final press = await tester.startGesture(tester.getCenter(_voice));
      await tester.pump(const Duration(milliseconds: 299));
      expect(rig.engine.isActive, isTrue);
      expect(rig.phase, DictationPhase.press);
      expect(find.text('0:00'), findsOneWidget);

      await press.up();
      await tester.pump();
      expect(rig.phase, DictationPhase.locked);
      expect(find.text('轻点结束'), findsOneWidget);
      final track = tester.getRect(_voice);
      expect(track.height, ComposerTokens.voiceHeight);
      expect(track.width, 390 - 2 * ComposerTokens.stripInset);

      rig.emit();
      await tester.tapAt(Offset(track.left + 6, track.center.dy));
      await tester.pumpAndSettle();
      expect(rig.phase, DictationPhase.review);
      expect(rig.editor.text, '左右');
    },
  );

  testWidgets('300 ms enters hold and releasing without a pull retains words', (
    tester,
  ) async {
    final rig = await _mount(tester);
    final press = await tester.startGesture(tester.getCenter(_voice));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(rig.phase, DictationPhase.hold);
    expect(find.bySemanticsLabel('上滑取消'), findsOneWidget);
    expect(_liquidPainter(tester).motion.goo.neck, isNull);

    rig.emit();
    await press.up();
    await tester.pumpAndSettle();
    expect(rig.phase, DictationPhase.review);
    expect(rig.editor.text, '左右');
  });

  testWidgets(
    'more than 10 dp initiates hold, and an attached pull ends on release',
    (tester) async {
      final rig = await _mount(tester);
      final origin = tester.getCenter(_voice);
      final press = await tester.startGesture(origin);
      await tester.pump();

      await press.moveTo(origin - const Offset(0, 10));
      await tester.pump();
      expect(rig.phase, DictationPhase.press);

      final pointer = origin - const Offset(0, 20);
      await press.moveTo(pointer);
      await tester.pump();
      expect(rig.phase, DictationPhase.hold);
      expect(rig.controller.value.pull, 30);
      expect(rig.controller.value.detached, isFalse);
      expect(find.text('继续上滑'), findsOneWidget);
      await _advance(tester, 16);
      final liquid = _liquidPainter(tester).motion;
      expect(liquid.goo.neck, isNotNull);
      expect(liquid.goo.blob, isNull);

      rig.emit();
      await press.up();
      expect(rig.controller.value.retracting, isTrue);
      expect(rig.phase, DictationPhase.hold);
      await tester.pumpAndSettle();
      expect(rig.phase, DictationPhase.review);
      expect(rig.editor.text, '左右');
      expect(liquid.goo.neck, isNull);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  for (final reconnect in [false, true]) {
    testWidgets(
      reconnect
          ? 'reconnecting at 78 dp retains words on release'
          : 'releasing a detached pull removes the inserted range',
      (tester) async {
        final rig = await _mount(tester);
        final origin = tester.getCenter(_voice);
        final press = await tester.startGesture(origin);
        await tester.pump();
        rig.emit();

        await press.moveTo(origin - const Offset(0, 98));
        await tester.pump();
        expect(rig.controller.value.pull, 110);
        expect(rig.controller.value.detached, isFalse);

        await press.moveTo(origin - const Offset(0, 99));
        await tester.pump();
        expect(rig.controller.value.detached, isTrue);
        expect(find.bySemanticsLabel('已断开，松手撤销'), findsOneWidget);
        final liquid = _liquidPainter(tester).motion;
        expect(liquid.goo.blob, isNotNull);
        expect(liquid.goo.label, isNotNull);
        expect(liquid.goo.label!.y, lessThan(liquid.goo.blob!.center.y));

        await press.moveTo(origin - const Offset(0, 67));
        await tester.pump();
        expect(rig.controller.value.pull, 79);
        expect(rig.controller.value.detached, isTrue);
        if (reconnect) {
          await press.moveTo(origin - const Offset(0, 66));
          await tester.pump();
          expect(rig.controller.value.pull, 78);
          expect(rig.controller.value.detached, isFalse);
          expect(liquid.goo.blob, isNull);
          expect(liquid.goo.label, isNull);
          expect(find.bySemanticsLabel('上滑取消'), findsOneWidget);
          expect(find.text('继续上滑'), findsOneWidget);
        }

        await press.up();
        if (!reconnect) {
          expect(rig.phase, DictationPhase.canceling);
          expect(rig.editor.text, '右');
          expect(rig.controller.active, isFalse);
          expect(rig.controller.value.holdBar, isTrue);
        }
        await tester.pumpAndSettle();
        expect(tester.binding.transientCallbackCount, 0);
        expect(
          rig.phase,
          reconnect ? DictationPhase.review : DictationPhase.idle,
        );
        expect(rig.editor.text, reconnect ? '左右' : '右');
      },
    );
  }

  testWidgets('break and rejoin have distinct haptics', (tester) async {
    final haptics = <Object?>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final rig = await _mount(tester);
    final origin = tester.getCenter(_voice);
    final press = await tester.startGesture(origin);
    await tester.pump();
    rig.emit();
    await press.moveTo(origin - const Offset(0, 99));
    await _advance(tester, 32);
    expect(
      rig.controller.visual.value.dropCenter!.dy,
      closeTo(origin.dy - 99 - 28, .1),
    );
    await press.moveTo(origin - const Offset(0, 66));
    await press.up();
    await tester.pumpAndSettle();
    expect(haptics, [
      'HapticFeedbackType.lightImpact',
      'HapticFeedbackType.mediumImpact',
      'HapticFeedbackType.lightImpact',
    ]);
  });

  testWidgets('a new press supersedes the flight and its liquid tail', (
    tester,
  ) async {
    final rig = await _mount(tester);
    final origin = tester.getCenter(_voice);
    final press = await tester.startGesture(origin);
    await tester.pump();
    rig.emit('这段话会被撤销');
    await press.moveTo(origin - const Offset(0, 99));
    await _advance(tester, 24);
    await press.up();
    await _advance(tester, 5);
    expect(rig.phase, DictationPhase.canceling);
    expect(rig.editor.text, '右');
    expect(rig.controller.visual.value.flyElapsed, isNotNull);
    expect(find.text('0:00'), findsOneWidget);

    final next = await tester.startGesture(tester.getCenter(_voice));
    await tester.pump();
    expect(rig.phase, DictationPhase.press);
    expect(rig.controller.visual.value.flyElapsed, isNull);
    final goo = _liquidPainter(tester).motion.goo;
    expect(goo.blob, isNull);
    expect(goo.red, isNull);
    expect(goo.parts, isEmpty);
    rig.emit('下一次');
    await next.up();
    await tester.pump();
    await tester.tap(_voice);
    await tester.pumpAndSettle();
    expect(rig.phase, DictationPhase.review);
    expect(rig.editor.text, '下一次右');
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('reduced motion draws a still drop and cancels without spray', (
    tester,
  ) async {
    final rig = await _mount(tester, reducedMotion: true);
    final origin = tester.getCenter(_voice);
    final press = await tester.startGesture(origin);
    await _advance(tester, 12);
    rig.emit();
    await press.moveTo(origin - const Offset(0, 99));
    await tester.pump();
    final motion = _liquidPainter(tester).motion;
    expect(motion.goo.blob, isNotNull);
    expect(motion.goo.parts, isEmpty);
    expect(motion.needsTick, isFalse);
    expect(tester.binding.transientCallbackCount, 1);

    await press.up();
    await tester.pump();
    expect(rig.editor.text, '右');
    expect(rig.phase, DictationPhase.canceling);
    await tester.pump(const Duration(milliseconds: 150));
    expect(motion.goo.blob, isNull);
    expect(motion.goo.parts, isEmpty);
    expect(motion.goo.ring, isNull);
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('only the silent notice expires after 2400 ms', (tester) async {
    final rig = await _mount(tester);
    await tester.tap(_voice);
    await tester.pump();
    rig.controller.finish();
    await tester.pump();
    final silent = find.text('没有听到声音，再试一次');
    expect(silent, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2399));
    expect(silent, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    expect(silent, findsNothing);
    await tester.pumpAndSettle();
  });

  testWidgets(
    'Enter or Space starts and ends, and Escape discards only dictated words',
    (tester) async {
      final rig = await _mount(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(rig.phase, DictationPhase.locked);
      rig.emit();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(rig.phase, DictationPhase.idle);
      expect(rig.editor.text, '右');

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(rig.phase, DictationPhase.locked);
      rig.emit();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(rig.phase, DictationPhase.review);
      expect(rig.editor.text, '左右');
    },
  );

  testWidgets(
    'semantics activation toggles listening and announces the character count',
    (tester) async {
      final rig = await _mount(tester, supportsAnnounce: true);
      _semanticsTap(tester, '语音输入');
      await tester.pump();
      expect(rig.phase, DictationPhase.locked);
      rig.emit('你👩‍💻');
      await tester.pump();

      _semanticsTap(tester, '轻点结束');
      await tester.pumpAndSettle();
      expect(rig.phase, DictationPhase.review);
      expect(tester.takeAnnouncements(), [
        isAccessibilityAnnouncement('已插入 2 字'),
      ]);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final undo = tester.getSemantics(find.bySemanticsLabel('撤销'));
      expect(
        undo.getSemanticsData().flagsCollection.isFocused,
        Tristate.isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(rig.editor.text, '右');
    },
  );

  testWidgets(
    'review exposes a live-region announcement without announce support',
    (tester) async {
      final rig = await _mount(tester);
      _semanticsTap(tester, '语音输入');
      await tester.pump();
      rig.emit();
      await tester.pump();
      _semanticsTap(tester, '轻点结束');
      await tester.pumpAndSettle();
      final announcement = tester.getSemantics(
        find.bySemanticsLabel('已插入 1 字'),
      );
      expect(
        announcement.getSemanticsData().flagsCollection.isLiveRegion,
        isTrue,
      );
    },
  );

  testWidgets('permission denial exposes settings only after the first press', (
    tester,
  ) async {
    const channel = MethodChannel('chh/update');
    final messenger = tester.binding.defaultBinaryMessenger;
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final engine = _DeniedMic();
    final rig = await _mount(tester, create: () => engine);
    expect(engine.startCalls, 0);
    expect(find.text('麦克风权限未开启'), findsNothing);

    await tester.tap(_voice);
    await tester.pumpAndSettle();
    expect(engine.startCalls, 1);
    expect(rig.phase, DictationPhase.errorPermission);
    expect(find.text('麦克风权限未开启'), findsOneWidget);
    expect(calls, isEmpty);

    await tester.tap(find.text('去设置'));
    await tester.pump();
    expect(calls, ['openAppSettings']);
    expect(rig.editor.text, '右');
  });

  testWidgets(
    '49, 50 and 59 seconds update the time label, color and wave clearance',
    (tester) async {
      final rig = await _mount(tester);
      final press = await tester.startGesture(tester.getCenter(_voice));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('0:03'), findsOneWidget);

      await tester.pump(const Duration(seconds: 46));
      final normal = tester.widget<Text>(find.text('0:49'));
      expect(normal.style?.color, ComposerTokens.voiceOnGradient);
      final normalLineLeft = _liquidPainter(tester).lineLeft;
      await tester.pump(const Duration(seconds: 1));
      final warning = tester.widget<Text>(find.text('还能说 10 秒'));
      expect(warning.style?.color, ComposerTokens.voiceTimeWarning);
      final warningLineLeft = _liquidPainter(tester).lineLeft;
      expect(warningLineLeft, greaterThan(normalLineLeft));
      await tester.pump(const Duration(seconds: 9));
      final last = tester.widget<Text>(find.text('还能说 1 秒'));
      expect(last.style?.color, ComposerTokens.voiceTimeWarning);
      expect(_liquidPainter(tester).lineLeft, lessThan(warningLineLeft));

      rig.emit();
      await press.up();
      await tester.pumpAndSettle();
      expect(rig.phase, DictationPhase.review);
      expect(find.text('已到 60 秒'), findsNothing);
    },
  );

  for (final reduced in [false, true]) {
    testWidgets('countdown pop honors reduced motion $reduced', (tester) async {
      final rig = await _mount(tester, reducedMotion: reduced);
      final press = await tester.startGesture(tester.getCenter(_voice));
      await tester.pump();
      await tester.pump(const Duration(seconds: 50));

      Finder pop(int seconds) => find.byWidgetPredicate(
        (widget) =>
            widget is TweenAnimationBuilder<double> &&
            widget.key == ValueKey(seconds),
      );
      double scale(int seconds) => tester
          .widget<Transform>(
            find.descendant(of: pop(seconds), matching: find.byType(Transform)),
          )
          .transform
          .entry(0, 0);

      expect(find.text('还能说 10 秒'), findsOneWidget);
      if (reduced) {
        expect(pop(50), findsNothing);
        await tester.pump(const Duration(seconds: 1));
        expect(pop(51), findsNothing);
      } else {
        expect(scale(50), 1.2);
        await tester.pump(const Duration(milliseconds: 300));
        expect(scale(50), lessThan(1));
        await tester.pump(const Duration(milliseconds: 320));
        expect(scale(50), 1);
        await tester.pump(const Duration(milliseconds: 380));
        expect(scale(51), 1.2);
      }
      rig.emit();
      await press.up();
      await tester.pumpAndSettle();
    });
  }

  testWidgets('ten-second warning sends exactly one polite announcement', (
    tester,
  ) async {
    final rig = await _mount(tester, supportsAnnounce: true);
    final press = await tester.startGesture(tester.getCenter(_voice));
    await tester.pump();
    await tester.pump(const Duration(seconds: 49));
    expect(tester.takeAnnouncements(), isEmpty);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeAnnouncements(), [
      isAccessibilityAnnouncement(
        '还能说 10 秒',
        assertiveness: Assertiveness.polite,
      ),
    ]);
    rig.engine.emitVolume(.8);
    await tester.pump();
    for (var i = 0; i < 9; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(tester.takeAnnouncements(), isEmpty);
    rig.emit();
    await press.up();
    await tester.pumpAndSettle();
  });

  testWidgets('countdown semantics is live only at the ten-second warning', (
    tester,
  ) async {
    final rig = await _mount(tester);
    final semantics = tester.ensureSemantics();
    final press = await tester.startGesture(tester.getCenter(_voice));
    final warning = find.bySemanticsLabel('还能说 10 秒');
    await tester.pump();
    await tester.pump(const Duration(seconds: 49));
    expect(warning, findsNothing);
    await tester.pump(const Duration(seconds: 1));
    final node = tester.getSemantics(warning);
    expect(node.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
    for (var i = 1; i <= 9; i++) {
      await tester.pump(const Duration(seconds: 1));
      final current = tester.getSemantics(
        find.bySemanticsLabel('还能说 ${10 - i} 秒'),
      );
      expect(current.id, node.id);
      expect(current.getSemanticsData().flagsCollection.isLiveRegion, isFalse);
    }
    expect(tester.takeAnnouncements(), isEmpty);
    rig.emit();
    await press.up();
    await tester.pumpAndSettle();
    expect(warning, findsNothing);
    semantics.dispose();
  });

  testWidgets('limit review labels the cause before undo and retry', (
    tester,
  ) async {
    final rig = await _mount(tester);
    final press = await tester.startGesture(tester.getCenter(_voice));
    await tester.pump();
    rig.emit();
    await tester.pump(const Duration(seconds: 60));
    await tester.pumpAndSettle();
    final limit = find.text('已到 60 秒');
    expect(rig.phase, DictationPhase.review);
    expect(
      tester.getCenter(limit).dx,
      lessThan(tester.getCenter(find.text('撤销')).dx),
    );
    expect(
      tester.getCenter(find.text('撤销')).dx,
      lessThan(tester.getCenter(find.text('重说')).dx),
    );
    final label = tester.widget<Text>(limit);
    expect(label.style?.color, AppTokens.mistyLight.text2);
    expect(label.style?.fontWeight, FontWeight.w600);
    await press.up();
  });

  testWidgets('limit without text keeps the silent notice', (tester) async {
    final rig = await _mount(tester);
    final press = await tester.startGesture(tester.getCenter(_voice));
    await tester.pump();
    await tester.pump(const Duration(seconds: 60));
    expect(rig.phase, DictationPhase.errorSilent);
    expect(find.text('没有听到声音，再试一次'), findsOneWidget);
    expect(find.text('已到 60 秒'), findsNothing);
    await press.up();
    await tester.pump(const Duration(milliseconds: 2400));
    await tester.pumpAndSettle();
  });

  testWidgets('limit while detached still starts undo flight', (tester) async {
    final rig = await _mount(tester);
    final origin = tester.getCenter(_voice);
    final press = await tester.startGesture(origin);
    await tester.pump();
    await _advance(tester, 25);
    rig.emit();
    await press.moveTo(origin - const Offset(0, 112));
    await tester.pump();
    expect(rig.controller.value.detached, isTrue);
    final painter = _liquidPainter(tester);
    await tester.pump(const Duration(milliseconds: 59600));
    expect(rig.phase, DictationPhase.canceling);
    expect(rig.editor.text, '右');
    expect(painter.motion.holdingForFly, isTrue);
    expect(find.text('已到 60 秒'), findsNothing);
    expect(_capacityPaint(painter), isNull);
    await press.up();
    await tester.pumpAndSettle();
    expect(rig.phase, DictationPhase.idle);
  });

  testWidgets(
    'capacity paint advances between seconds and changes tint at 50',
    (tester) async {
      final rig = await _mount(tester, reducedMotion: true);
      final press = await tester.startGesture(tester.getCenter(_voice));
      await tester.pump();
      await tester.pump(const Duration(seconds: 30));
      final painter = _liquidPainter(tester);
      final first = _capacityPaint(painter)!;
      expect(first.rect.left, 0);
      expect(first.rect.width, closeTo(painter.fullWidth * .5, .0001));
      expect(first.color, isSameColorAs(const Color(0x33FFFFFF)));
      await tester.pump(const Duration(milliseconds: 250));
      expect(_liquidPainter(tester), same(painter));
      expect(
        _capacityPaint(painter)!.rect.width,
        closeTo(painter.fullWidth * 30.25 / 60, .0001),
      );
      await tester.pump(const Duration(milliseconds: 19749));
      expect(
        _capacityPaint(_liquidPainter(tester))!.color,
        isSameColorAs(const Color(0x33FFFFFF)),
      );
      await tester.pump(const Duration(milliseconds: 1));
      final warning = _capacityPaint(_liquidPainter(tester))!;
      expect(warning.rect.width, closeTo(painter.fullWidth * 50 / 60, .0001));
      expect(
        warning.color,
        isSameColorAs(const Color(0xFFFFE7A6).withValues(alpha: .32)),
      );
      rig.emit();
      await press.up();
      expect(_capacityPaint(painter), isNull);
      await tester.pumpAndSettle();
      expect(rig.phase, DictationPhase.review);
    },
  );

  testWidgets('capacity is clipped to the waved bar below the attached drop', (
    tester,
  ) async {
    final rig = await _mount(tester);
    final origin = tester.getCenter(_voice);
    final press = await tester.startGesture(origin);
    await tester.pump();
    await tester.pump(const Duration(seconds: 45));
    await press.moveTo(origin - const Offset(0, 60));
    await _advance(tester, 40);
    final capacity = _capacityPaint(_liquidPainter(tester))!;
    expect(capacity.clips, hasLength(2));
    final body = capacity.clips.last;
    final full = capacity.clips.first;
    expect(body.getBounds().top, greaterThan(full.getBounds().top + 20));
    expect(capacity.rect.top, body.getBounds().top);
    expect(body.getBounds().left, full.getBounds().left);
    expect(body.getBounds().bottom, full.getBounds().bottom);
    // A level inside the animated rim sits above the capsule's nominal top.
    expect(
      body.getBounds().top,
      lessThan(ComposerTokens.voiceHeight - body.getBounds().bottom),
    );
    rig.emit();
    await press.up();
    await tester.pumpAndSettle();
  });
}

({Rect rect, Color color, List<Path> clips})? _capacityPaint(
  VoiceLiquidPainter painter,
) {
  final canvas = TestRecordingCanvas();
  painter.paint(canvas, Size.zero);
  final clips = <Path>[];
  for (final record in canvas.invocations) {
    final call = record.invocation;
    if (call.memberName == #clipPath) {
      clips.add(call.positionalArguments.first as Path);
    }
    if (call.memberName != #drawRect) continue;
    if (call.positionalArguments case [
      final Rect rect,
      final Paint paint,
    ] when paint.shader == null) {
      return (rect: rect, color: paint.color, clips: clips);
    }
  }
  return null;
}

Future<void> _advance(WidgetTester tester, int frames) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void _semanticsTap(WidgetTester tester, String label) {
  final node = tester.getSemantics(find.bySemanticsLabel(label));
  node.owner!.performAction(node.id, SemanticsAction.tap);
}

Future<_VoiceRig> _mount(
  WidgetTester tester, {
  bool supportsAnnounce = false,
  bool reducedMotion = false,
  FakeSpeechEngine Function()? create,
}) async {
  final rig = _VoiceRig(tester, create);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light, AppearanceStyle.misty),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 390,
            child: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  supportsAnnounce: supportsAnnounce,
                  disableAnimations: reducedMotion,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    VoiceStatus(controller: rig.controller),
                    ListenableBuilder(
                      listenable: rig.controller,
                      builder: (context, _) => ComposerToolStrip(
                        voice: VoiceBar(controller: rig.controller),
                        voiceActive: rig.controller.barExpanded,
                        send: const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return rig;
}

class _VoiceRig {
  final editor = TextEditingController.fromValue(
    const TextEditingValue(
      text: '右',
      selection: TextSelection.collapsed(offset: 0),
    ),
  );
  late final DictationController controller;
  late FakeSpeechEngine engine;

  _VoiceRig(WidgetTester tester, FakeSpeechEngine Function()? create) {
    controller = DictationController(
      editor: editor,
      createEngine: () => engine = create?.call() ?? FakeSpeechEngine(),
      clock: _TestClock(tester),
    );
    addTearDown(() {
      controller.dispose();
      editor.dispose();
    });
  }

  DictationPhase get phase => controller.value.phase;

  void emit([String words = '左']) =>
      engine.emitText(SpeechText(finalized: '', interim: words));
}

VoiceLiquidPainter _liquidPainter(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is CustomPaint &&
                    widget.painter is VoiceLiquidPainter,
              ),
            )
            .painter!
        as VoiceLiquidPainter;

class _DelayedMic extends FakeSpeechEngine {
  final ready = Completer<void>();

  @override
  Future<void> start() async {
    await ready.future;
    await super.start();
  }
}

class _DeniedMic extends FakeSpeechEngine {
  int startCalls = 0;

  @override
  Future<void> start() async {
    startCalls++;
    await super.start();
    emitError(SpeechErrorKind.permission);
  }
}

class _TestClock implements SpeechClock {
  final WidgetTester tester;
  final DateTime _origin;

  _TestClock(this.tester) : _origin = tester.binding.clock.now();

  @override
  Duration get elapsed => tester.binding.clock.now().difference(_origin);

  @override
  Timer schedule(Duration delay, void Function() callback) =>
      Timer(delay, callback);
}
