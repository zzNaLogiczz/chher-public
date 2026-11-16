import 'dart:ui' show Tristate;

import 'package:chh_app/core/app_info.dart';
import 'package:chh_app/core/appearance.dart';
import 'package:chh_app/data/image_disk_cache.dart';
import 'package:chh_app/design/icons.dart';
import 'package:solar_icons/solar_icons.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/di.dart';
import 'package:chh_app/pages/settings_page.dart';
import 'package:chh_app/widgets/settings_appearance.dart';
import 'package:chh_app/ui/sheet_scaffold.dart';
import 'package:chh_app/design/sheet_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _LocalCache extends ImageDiskCache {
  _LocalCache() : super(null);

  int clearCalls = 0;

  @override
  Future<int> totalBytes() async => 1536;

  @override
  Future<void> clear() async {
    clearCalls++;
  }
}

Widget _app(AppearanceController controller) => ListenableBuilder(
  listenable: controller,
  builder: (_, _) => MaterialApp(
    theme: buildAppTheme(Brightness.light, controller.style),
    darkTheme: buildAppTheme(Brightness.dark, controller.style),
    themeMode: controller.mode.themeMode,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: const TextScaler.linear(1.3),
        padding: const EdgeInsets.only(top: 24),
      ),
      child: child!,
    ),
    home: SettingsPage(appearanceController: controller),
  ),
);

Future<void> _show(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    150,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void main() {
  late ImageDiskCache originalCache;
  late _LocalCache cache;
  late AppearanceController controller;
  late bool wasLoggedIn;

  setUp(() {
    originalCache = imageDiskCache;
    cache = _LocalCache();
    imageDiskCache = cache;
    wasLoggedIn = chhSession.loggedIn;
    chhSession.loggedIn = true;
    controller = AppearanceController(directory: () async => null);
  });

  tearDown(() {
    imageDiskCache = originalCache;
    chhSession.loggedIn = wasLoggedIn;
    controller.dispose();
  });

  for (final style in AppearanceStyle.values) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'shared flat settings fits 360x640 at 1.3x: $style $brightness',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(360, 640));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          controller.setStyle(style);
          controller.set(
            brightness == Brightness.dark
                ? AppearanceMode.dark
                : AppearanceMode.light,
          );
          await tester.pumpWidget(_app(controller));
          await tester.pumpAndSettle();

          expect(find.text('外观'), findsOneWidget);
          expect(find.byType(StylePreviewCard), findsNWidgets(2));
          for (final previewStyle in AppearanceStyle.values) {
            final preview = tester.widget<StylePreviewCard>(
              find.byKey(ValueKey('settings-style-${previewStyle.name}')),
            );
            expect(preview.selected, previewStyle == style);
            expect(preview.dot, previewStyle == AppearanceStyle.cinnabar);
          }
          expect(find.text('薄暮'), findsOneWidget);
          expect(find.text('朱砂'), findsOneWidget);
          expect(
            tester.getCenter(find.text('薄暮')).dx,
            lessThan(tester.getCenter(find.text('朱砂')).dx),
          );
          for (final label in ['跟随系统', '浅色', '深色']) {
            expect(find.text(label), findsOneWidget);
          }
          final tokens = AppTokens.of(tester.element(find.text('薄暮')));
          expect(tokens.style, style);
          expect(tokens.isDark, brightness == Brightness.dark);
          final check = tester.widget<Icon>(
            find.descendant(
              of: find.byKey(ValueKey('settings-style-${style.name}')),
              matching: find.byIcon(Icons.check_rounded),
            ),
          );
          expect(check.color, SettingsTokens.strongForeground(tokens));
          final luminances = [
            check.color!.computeLuminance(),
            tokens.accent.computeLuminance(),
          ]..sort();
          expect(
            (luminances.last + .05) / (luminances.first + .05),
            greaterThanOrEqualTo(3),
          );
          expect(tester.takeException(), isNull);

          await _show(tester, find.text('图片缓存'));
          expect(find.text('通用'), findsOneWidget);
          expect(find.text('1.5 KB'), findsOneWidget);
          expect(
            find.byIcon(SolarIconsBold.galleryMinimalistic),
            findsOneWidget,
          );
          await tester.tap(find.text('图片缓存'));
          await tester.pumpAndSettle();
          expect(find.text('清除图片缓存？'), findsOneWidget);
          await tester.tap(find.text('取消'));
          await tester.pumpAndSettle();
          expect(cache.clearCalls, 0);
          expect(find.text('1.5 KB'), findsOneWidget);

          await _show(tester, find.text('运行日志'));
          expect(find.byIcon(AppIcons.logBold), findsOneWidget);
          await _show(tester, find.byKey(const ValueKey('settings-about')));
          expect(find.text('关于 Chher'), findsOneWidget);
          expect(find.text(AppInfo.version), findsOneWidget);
          expect(find.byType(Image), findsOneWidget);

          await _show(tester, find.text('退出登录'));
          final logout = find.byKey(const ValueKey('settings-logout'));
          expect(tester.getSize(logout).height, 44);
          final surface = tester.widget<DecoratedBox>(
            find
                .ancestor(
                  of: logout,
                  matching: find.byWidgetPredicate(
                    (w) => w is DecoratedBox && w.decoration is ShapeDecoration,
                  ),
                )
                .first,
          );
          final shape =
              (surface.decoration as ShapeDecoration).shape
                  as RoundedSuperellipseBorder;
          expect(
            shape.borderRadius.resolve(TextDirection.ltr).topLeft.x,
            AppRadii.full,
          );
          await tester.tap(find.text('退出登录'));
          await tester.pumpAndSettle();
          expect(find.text('退出当前账号？'), findsOneWidget);
          await tester.tap(find.text('取消'));
          await tester.pumpAndSettle();
          expect(chhSession.loggedIn, isTrue);
          expect(controller.styleDotSeen, isFalse);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          expect(controller.styleDotSeen, isTrue);
        },
      );
    }
  }

  testWidgets(
    'style previews and mode controls update the shared theme with smooth animation',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final dispatcher = tester.binding.platformDispatcher;
        dispatcher.platformBrightnessTestValue = Brightness.light;
        addTearDown(dispatcher.clearPlatformBrightnessTestValue);
        await tester.pumpWidget(_app(controller));
        await tester.pumpAndSettle();

        // Cards select in place; only their inner outline fades, with no sliding panel.
        await tester.tap(find.text('朱砂'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 90));
        final outline = tester.widget<DecoratedBox>(
          find.byKey(const ValueKey('settings-style-outline-cinnabar')),
        );
        final border =
            ((outline.decoration as ShapeDecoration).shape as OutlinedBorder)
                .side;
        expect(border.width, SettingsTokens.selectionWidth);
        expect(border.color.a, greaterThan(0));
        expect(border.color.a, lessThan(1));

        for (final style in [AppearanceStyle.cinnabar, AppearanceStyle.misty]) {
          await tester.tap(find.text(style.label));
          await tester.pumpAndSettle();
          expect(controller.style, style);
          final selectedPreview = find.byKey(
            ValueKey('settings-style-${style.name}'),
          );
          final node = tester.getSemantics(selectedPreview);
          expect(node.flagsCollection.isButton, isTrue);
          expect(node.flagsCollection.isSelected, Tristate.isTrue);
          expect(node.label, style.label);
          expect(
            AppTokens.of(tester.element(find.text(style.label))).style,
            style,
          );
        }
        for (final mode in [
          AppearanceMode.dark,
          AppearanceMode.light,
          AppearanceMode.system,
        ]) {
          await tester.tap(find.text(mode.label));
          await tester.pumpAndSettle();
          expect(controller.mode, mode);
          final selectedMode = find.byKey(
            ValueKey('settings-mode-${mode.name}'),
          );
          expect(tester.getSize(selectedMode).height, greaterThanOrEqualTo(44));
          final node = tester.getSemantics(selectedMode);
          expect(node.flagsCollection.isButton, isTrue);
          expect(node.flagsCollection.isSelected, Tristate.isTrue);
          expect(node.label, mode.label);
          expect(
            tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
            mode.themeMode,
          );
          expect(
            AppTokens.of(tester.element(find.text(mode.label))).isDark,
            mode == AppearanceMode.dark,
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('guest settings omits logout while keeping tools reachable', (
    tester,
  ) async {
    chhSession.loggedIn = false;
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();
    await _show(tester, find.byKey(const ValueKey('settings-about')));
    expect(find.text('退出登录'), findsNothing);
    expect(find.text('关于 Chher'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('dragging mode slider and style cards switches smoothly', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    final systemPos = tester.getCenter(
      find.byKey(ValueKey('settings-mode-${AppearanceMode.system.name}')),
    );
    final darkPos = tester.getCenter(
      find.byKey(ValueKey('settings-mode-${AppearanceMode.dark.name}')),
    );
    await tester.dragFrom(systemPos, darkPos - systemPos);
    await tester.pumpAndSettle();
    expect(controller.mode, AppearanceMode.dark);

    final mistyPos = tester.getCenter(
      find.byKey(ValueKey('settings-style-${AppearanceStyle.misty.name}')),
    );
    final cinnabarPos = tester.getCenter(
      find.byKey(ValueKey('settings-style-${AppearanceStyle.cinnabar.name}')),
    );
    await tester.dragFrom(mistyPos, cinnabarPos - mistyPos);
    await tester.pumpAndSettle();
    expect(controller.style, AppearanceStyle.cinnabar);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'mode track keeps 44/4/36 geometry and interrupted spring settles',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_app(controller));
      await tester.pumpAndSettle();
      final track = find.byKey(const ValueKey('settings-mode-track'));
      final thumb = find.byKey(const ValueKey('settings-mode-thumb'));
      expect(tester.getSize(track).height, 44);
      expect(tester.getSize(thumb).height, 36);
      expect(tester.getTopLeft(thumb).dy - tester.getTopLeft(track).dy, 4);
      expect(tester.getTopLeft(thumb).dx - tester.getTopLeft(track).dx, 4);
      final start = tester.getTopLeft(thumb).dx;
      await tester.tap(find.text('深色'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.getTopLeft(thumb).dx, greaterThan(start));
      await tester.tap(find.text('跟随系统'));
      await tester.pumpAndSettle();
      expect(controller.mode, AppearanceMode.system);
      expect(tester.getTopLeft(thumb).dx, closeTo(start, .01));
      expect(tester.binding.transientCallbackCount, 0);
      expect(find.byType(Divider), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'logout uses inset shared sheet with only title and two actions',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_app(controller));
      await tester.pumpAndSettle();
      await _show(tester, find.text('退出登录'));
      await tester.tap(find.text('退出登录'));
      await tester.pumpAndSettle();
      final sheet = find.byType(AppSheetSurface);
      expect(sheet, findsOneWidget);
      final labels = tester
          .widgetList<Text>(
            find.descendant(of: sheet, matching: find.byType(Text)),
          )
          .map((t) => t.data)
          .toList();
      expect(labels, ['退出当前账号？', '退出', '取消']);
      expect(tester.getRect(sheet).left, AppSheetTokens.inset);
      expect(tester.getRect(sheet).right, 390 - AppSheetTokens.inset);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(chhSession.loggedIn, isTrue);
      expect(find.byType(AppSheetSurface), findsNothing);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('AppTokens.lerp smoothly interpolates colors across style and mode', () {
    final mid = AppTokens.mistyLight.lerp(AppTokens.mistyDark, 0.5);
    expect(
      mid.bg,
      isSameColorAs(
        Color.lerp(AppTokens.mistyLight.bg, AppTokens.mistyDark.bg, 0.5)!,
      ),
    );
    expect(
      mid.accent,
      isSameColorAs(
        Color.lerp(
          AppTokens.mistyLight.accent,
          AppTokens.mistyDark.accent,
          0.5,
        )!,
      ),
    );
  });
}
