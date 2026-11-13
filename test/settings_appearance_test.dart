import 'package:chh_app/core/appearance.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/pages/settings_page.dart';
import 'package:chh_app/widgets/settings_appearance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppearanceController controller;

  setUp(() {
    controller = AppearanceController(directory: () async => null);
  });

  tearDown(() => controller.dispose());

  testWidgets('风格预览与明暗模式在同一平面分组里随列表滚动', (tester) async {
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    final appearance = find.byType(SettingsAppearance);
    final section = find.byKey(const ValueKey('settings-appearance'));
    expect(appearance, findsOneWidget);
    expect(
      find.descendant(of: section, matching: appearance),
      findsOneWidget,
    );
    expect(
      tester.getRect(section).left -
          tester.getRect(find.byType(ListView)).left,
      AppSpace.groupInset,
    );
    expect(
      tester.widget<Text>(find.text('外观与风格')).style,
      tester.widget<Text>(find.text('存储与诊断')).style,
    );
    expect(
      tester.getTopLeft(find.text('外观与风格')).dy,
      lessThan(tester.getTopLeft(appearance).dy),
    );
    expect(
      find.ancestor(of: appearance, matching: find.byType(ListView)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: appearance, matching: find.byType(StylePreviewCard)),
      findsNWidgets(2),
    );
    final previews = find.byType(StylePreviewCard);
    for (final mode in AppearanceMode.values) {
      final control = find.byKey(ValueKey('settings-mode-${mode.name}'));
      expect(
        find.descendant(of: control, matching: find.text(mode.label)),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(control).dy,
        greaterThan(tester.getBottomLeft(previews.first).dy),
      );
    }
    expect(
      tester.getBottomLeft(appearance).dy,
      lessThan(tester.getTopLeft(find.text('存储与诊断')).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('手动外观覆盖系统亮度，跟随系统恢复系统主题', (tester) async {
    final dispatcher = tester.binding.platformDispatcher;
    dispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(dispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );
    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();
    expect(controller.mode, AppearanceMode.dark);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    expect(
      Theme.of(tester.element(find.text('深色'))).brightness,
      Brightness.dark,
    );
    expect(AppTokens.of(tester.element(find.text('深色'))).isDark, isTrue);

    dispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    await tester.tap(find.text('浅色'));
    await tester.pumpAndSettle();
    expect(controller.mode, AppearanceMode.light);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.light,
    );
    expect(
      Theme.of(tester.element(find.text('浅色'))).brightness,
      Brightness.light,
    );

    await tester.tap(find.text('跟随系统'));
    await tester.pumpAndSettle();
    expect(controller.mode, AppearanceMode.system);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );
    expect(
      Theme.of(tester.element(find.text('跟随系统'))).brightness,
      Brightness.dark,
    );
    expect(tester.takeException(), isNull);
  });
}

Widget _app(AppearanceController controller) => ListenableBuilder(
  listenable: controller,
  builder: (_, _) => MaterialApp(
    theme: buildAppTheme(Brightness.light),
    darkTheme: buildAppTheme(Brightness.dark),
    themeMode: controller.mode.themeMode,
    home: SettingsPage(appearanceController: controller),
  ),
);
