import 'package:chh_app/design/system_ui.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/widgets/lac_scaffold.dart';
import 'package:chh_app/widgets/launch_splash.dart';
import 'package:chh_app/widgets/image_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void _screen(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1
    ..padding = const FakeViewPadding(top: 24, bottom: 24)
    ..viewPadding = const FakeViewPadding(top: 24, bottom: 24);
  addTearDown(() {
    tester.view.reset();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle());
  });
}

void _expectStatus(Brightness icons) {
  final style = SystemChrome.latestStyle!;
  expect(style.statusBarColor, Colors.transparent);
  expect(style.systemStatusBarContrastEnforced, isFalse);
  expect(style.statusBarIconBrightness, icons);
}

void main() {
  test(
    'status styles remove the scrim without changing bottom system bars',
    () {
      for (final style in [AppSystemUi.lightIcons, AppSystemUi.darkIcons]) {
        expect(style.statusBarColor, Colors.transparent);
        expect(style.systemStatusBarContrastEnforced, isFalse);
        expect(style.systemNavigationBarColor, isNull);
        expect(style.systemNavigationBarIconBrightness, isNull);
        expect(style.systemNavigationBarContrastEnforced, isNull);
      }
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets('image viewer keeps light status icons: $brightness', (
      tester,
    ) async {
      _screen(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(brightness),
          home: const ImageViewerPage(urls: []),
        ),
      );
      await tester.pumpAndSettle();
      _expectStatus(Brightness.light);
    });
    for (final appearance in AppearanceStyle.values) {
      testWidgets(
        'launch and AppBar stay transparent: $appearance $brightness',
        (tester) async {
          _screen(tester);
          final theme = buildAppTheme(brightness, appearance);
          await tester.pumpWidget(
            MaterialApp(theme: theme, home: const LaunchSplash()),
          );
          await tester.pumpAndSettle();
          _expectStatus(
            appearance == AppearanceStyle.cinnabar ||
                    brightness == Brightness.dark
                ? Brightness.light
                : Brightness.dark,
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(appBar: AppBar(title: const Text('纸面页面'))),
            ),
          );
          await tester.pumpAndSettle();
          _expectStatus(
            brightness == Brightness.dark ? Brightness.light : Brightness.dark,
          );
        },
      );
    }

    testWidgets(
      'red header keeps transparency when scrolling to paper: $brightness',
      (tester) async {
        _screen(tester);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(brightness),
            home: LacScaffold(
              title: '版块',
              body: ListView.builder(
                itemCount: 60,
                itemBuilder: (_, i) =>
                    SizedBox(height: 80, child: Text('版块 $i')),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        _expectStatus(Brightness.light);
        final header = find
            .descendant(of: find.byType(LacScaffold), matching: find.text('版块'))
            .first;
        expect(tester.getTopLeft(header).dy, greaterThanOrEqualTo(24));
        await tester.drag(find.byType(ListView), const Offset(0, -500));
        await tester.pumpAndSettle();
        _expectStatus(
          brightness == Brightness.dark ? Brightness.light : Brightness.dark,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
