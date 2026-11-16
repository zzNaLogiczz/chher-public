import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:chh_app/core/appearance.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/theme_reveal.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/widgets/settings_appearance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppearanceController appearance;
  late GlobalKey<ThemeRevealState> reveal;

  setUp(() {
    appearance = AppearanceController(directory: () async => null);
    reveal = GlobalKey<ThemeRevealState>();
  });
  tearDown(() => appearance.dispose());

  Widget app({bool reduced = false}) => ListenableBuilder(
    listenable: appearance,
    builder: (context, _) => MaterialApp(
      theme: buildAppTheme(Brightness.light, appearance.style),
      darkTheme: buildAppTheme(Brightness.dark, appearance.style),
      themeMode: appearance.mode.themeMode,
      themeAnimationDuration: Duration.zero,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
        child: ThemeReveal(key: reveal, appearance: appearance, child: child!),
      ),
      home: Scaffold(body: SettingsAppearance(controller: appearance)),
    ),
  );

  testWidgets(
    'old theme covers the first frame and survives unchanged viewport metrics',
    (tester) async {
      final frameKey = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(key: frameKey, child: app()));
      await tester.pumpAndSettle();
      // Settings normally sits above another route, inside the root Navigator.
      Navigator.of(tester.element(find.byType(SettingsAppearance))).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              Scaffold(body: SettingsAppearance(controller: appearance)),
        ),
      );
      await tester.pumpAndSettle();
      final boundary =
          frameKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final option = find.byKey(const ValueKey('settings-mode-dark'));
      final origin = tester.getCenter(option);
      final points = [
        origin + const Offset(0, 80),
        Offset(20, boundary.size.height - 20),
      ];
      Future<List<List<int>>> sample(ui.Image image) async {
        final bytes = (await tester.runAsync(
          () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
        ))!;
        final rgba = bytes.buffer.asUint8List();
        final scale = image.width / boundary.size.width;
        return [
          for (final point in points)
            rgba.sublist(
              ((point.dy * scale).floor() * image.width +
                      (point.dx * scale).floor()) *
                  4,
              ((point.dy * scale).floor() * image.width +
                          (point.dx * scale).floor()) *
                      4 +
                  4,
            ),
        ];
      }

      Future<List<List<int>>> frame() async {
        final image = boundary.toImageSync();
        final pixels = await sample(image);
        image.dispose();
        return pixels;
      }

      final before = await frame();
      final gesture = await tester.startGesture(origin);
      await tester.pump(const Duration(milliseconds: 90));
      await gesture.up();
      final snapshot = reveal.currentState!.debugSnapshot!;
      expect(
        await sample(snapshot),
        before,
        reason: 'capture precedes the theme change',
      );
      // Android can resend viewport metrics while changing system bar appearance.
      tester.binding.handleMetricsChanged();
      expect(reveal.currentState!.debugSnapshot, same(snapshot));
      await tester.pump();
      expect(AppTokens.of(tester.element(option)).isDark, isTrue);
      expect(
        await frame(),
        before,
        reason: 'old pixels cover the newly built theme',
      );
      await tester.pump(const Duration(milliseconds: 50));
      final during = await frame();
      expect(
        during.first,
        isNot(before.first),
        reason: 'new theme appears near the touch',
      );
      expect(
        during.last,
        before.last,
        reason: 'old theme stays outside the circle',
      );
      await tester.pumpAndSettle();
      expect(await frame(), [during.first, during.first]);
      expect(reveal.currentState!.debugSnapshot, isNull);
      expect(snapshot.debugDisposed, isTrue);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('pending paint captures the displayed frame before switching', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find
          .descendant(
            of: find.byType(ThemeReveal),
            matching: find.byWidgetPredicate(
              (widget) => widget is RepaintBoundary,
            ),
          )
          .first,
    );
    boundary.markNeedsPaint();
    await tester.tap(find.byKey(const ValueKey('settings-mode-dark')));
    final image = reveal.currentState!.debugSnapshot;
    expect(image, isNotNull);
    await tester.pump();
    expect(image!.debugDisposed, isFalse);
    await tester.pumpAndSettle();
    expect(image.debugDisposed, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a resized viewport releases an obsolete snapshot', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-mode-dark')));
    final image = reveal.currentState!.debugSnapshot!;
    tester.view.physicalSize = tester.view.physicalSize + const Offset(0, 30);
    addTearDown(tester.view.resetPhysicalSize);
    expect(reveal.currentState!.debugSnapshot, isNull);
    expect(image.debugDisposed, isTrue);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'style and mode taps reveal from global contact and dispose image',
    (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      for (final entry in [
        ('settings-style-cinnabar', AppearanceStyle.cinnabar, false),
        ('settings-mode-dark', AppearanceStyle.cinnabar, true),
        ('settings-style-misty', AppearanceStyle.misty, true),
        ('settings-mode-light', AppearanceStyle.misty, false),
      ]) {
        final option = find.byKey(ValueKey(entry.$1));
        final origin = tester.getCenter(option);
        await tester.tapAt(origin);
        final image = reveal.currentState!.debugSnapshot;
        expect(image, isNotNull);
        expect(reveal.currentState!.debugSnapshotOrigin, origin);
        await tester.pump();
        final tokens = AppTokens.of(tester.element(option));
        expect(tokens.style, entry.$2);
        expect(tokens.isDark, entry.$3);
        expect(image!.debugDisposed, isFalse);
        await tester.pumpAndSettle();
        expect(reveal.currentState!.debugSnapshot, isNull);
        expect(image.debugDisposed, isTrue);
        expect(tester.binding.transientCallbackCount, 0);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'another theme tap interrupts and releases the previous snapshot',
    (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-style-cinnabar')));
      final first = reveal.currentState!.debugSnapshot!;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));
      await tester.tap(find.byKey(const ValueKey('settings-mode-dark')));
      final second = reveal.currentState!.debugSnapshot!;
      expect(first.debugDisposed, isTrue);
      expect(second.debugDisposed, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(second.debugDisposed, isTrue);
    },
  );

  testWidgets('system brightness fades snapshot for 180ms without an origin', (
    tester,
  ) async {
    final dispatcher = tester.binding.platformDispatcher;
    dispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(dispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    dispatcher.platformBrightnessTestValue = Brightness.dark;
    final image = reveal.currentState!.debugSnapshot;
    expect(image, isNotNull);
    expect(reveal.currentState!.debugSnapshotOrigin, isNull);
    await tester.pump();
    expect(
      AppTokens.of(tester.element(find.byType(SettingsAppearance))).isDark,
      isTrue,
    );
    await tester.pump(const Duration(milliseconds: 179));
    expect(image!.debugDisposed, isFalse);
    await tester.pump(const Duration(milliseconds: 2));
    expect(image.debugDisposed, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('explicit mode ignores system brightness', (tester) async {
    appearance.set(AppearanceMode.light);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.dark;
    addTearDown(
      tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
    );
    expect(reveal.currentState!.debugSnapshot, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('reduced motion switches immediately without capturing', (
    tester,
  ) async {
    await tester.pumpWidget(app(reduced: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-style-cinnabar')));
    await tester.pump();
    expect(appearance.style, AppearanceStyle.cinnabar);
    expect(reveal.currentState!.debugSnapshot, isNull);
    expect(
      tester
          .widget<StylePreviewCard>(
            find.byKey(const ValueKey('settings-style-cinnabar')),
          )
          .emphasis,
      1,
    );
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
