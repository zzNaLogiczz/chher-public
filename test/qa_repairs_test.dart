/// Offline regressions for the accepted 1.0.4 QA repairs.
library;

import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/di.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/forum_index_view.dart';
import 'package:chh_app/pages/home_page.dart';
import 'package:chh_app/widgets/app_shell.dart';
import 'package:chh_app/ui/nav_bar.dart';
import 'package:chh_app/pages/log_page.dart';
import 'package:chh_app/pages/settings_page.dart';
import 'package:chh_app/ui/app_button.dart';
import 'package:chh_app/ui/press.dart';
import 'package:chh_app/ui/sheet_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _capture = bool.fromEnvironment('QA_REPAIR_SCREENSHOTS');
final _boundary = GlobalKey();

Future<void> _shot(WidgetTester tester, String name) async {
  if (!_capture) return;
  final boundary =
      _boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('build/qa/repairs-20261030');
    await dir.create(recursive: true);
    await File(
      '${dir.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Widget _app(Widget page, Brightness brightness, double scale) =>
    RepaintBoundary(
      key: _boundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _capture
            ? buildAppTheme(brightness).copyWith(
                dialogTheme: buildAppTheme(brightness).dialogTheme.copyWith(
                  titleTextStyle: buildAppTheme(
                    brightness,
                  ).dialogTheme.titleTextStyle!.copyWith(fontFamily: 'QA'),
                ),
                textTheme: buildAppTheme(
                  brightness,
                ).textTheme.apply(fontFamily: 'QA'),
              )
            : buildAppTheme(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: page,
      ),
    );

double _contrast(Color a, Color b) {
  final x = a.computeLuminance();
  final y = b.computeLuminance();
  return (x > y ? x + .05 : y + .05) / (x > y ? y + .05 : x + .05);
}

void main() {
  setUpAll(() async {
    // Real CJK metrics for the optional offline screenshots; no bundled font.
    if (_capture) {
      final file = File('/System/Library/Fonts/STHeiti Medium.ttc');
      for (final family in ['QA', 'Ahem', 'Roboto']) {
        await (FontLoader(family)..addFont(
              Future.value(ByteData.sublistView(file.readAsBytesSync())),
            ))
            .load();
      }
      final config = File('.dart_tool/package_config.json');
      final packages =
          (jsonDecode(config.readAsStringSync()) as Map)['packages'] as List;
      final solar = packages.cast<Map>().firstWhere(
        (p) => p['name'] == 'solar_icons',
      );
      final root = Directory.fromUri(
        config.absolute.uri.resolve(solar['rootUri'] as String),
      ).uri;
      final iconFont = File.fromUri(root.resolve('fonts/SolarIcons.ttf'));
      await (FontLoader('packages/solar_icons/SolarIcons')..addFont(
            Future.value(ByteData.sublistView(iconFont.readAsBytesSync())),
          ))
          .load();
      for (final entry in [
        (
          'cupertino_icons',
          'assets/CupertinoIcons.ttf',
          'packages/cupertino_icons/CupertinoIcons',
        ),
        (
          'flutter',
          '../../bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          'MaterialIcons',
        ),
      ]) {
        final package = packages.cast<Map>().firstWhere(
          (p) => p['name'] == entry.$1,
        );
        final packageRoot = Directory.fromUri(
          config.absolute.uri.resolve(package['rootUri'] as String),
        ).uri;
        final font = File.fromUri(packageRoot.resolve(entry.$2));
        await (FontLoader(entry.$3)..addFont(
              Future.value(ByteData.sublistView(font.readAsBytesSync())),
            ))
            .load();
      }
    }
  });
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      for (final kind in ['cache', 'logout', 'logs']) {
        testWidgets('$kind rendered dialog $brightness scale $scale', (
          tester,
        ) async {
          tester.view.physicalSize = Size(scale == 2 ? 320 : 390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          chhSession.loggedIn = true;
          addTearDown(() => chhSession.loggedIn = false);
          await tester.pumpWidget(
            _app(
              kind == 'logs' ? const LogPage() : const SettingsPage(),
              brightness,
              scale,
            ),
          );
          await tester.pumpAndSettle();
          final trigger = kind == 'logs'
              ? find.byTooltip('清空日志')
              : find.text(kind == 'cache' ? '图片缓存' : '退出登录');
          if (trigger.evaluate().isEmpty) {
            await tester.scrollUntilVisible(
              trigger,
              250,
              scrollable: find.byType(Scrollable).last,
            );
          }
          await tester.ensureVisible(trigger);
          await tester.pumpAndSettle();
          await tester.tap(trigger);
          await tester.pumpAndSettle();
          final isSheet = kind != 'logs';
          final dialog = isSheet
              ? find.byType(AppSheetSurface)
              : find.byType(AlertDialog);
          final Color surface;
          if (isSheet) {
            final decoration =
                tester
                        .widget<DecoratedBox>(
                          find
                              .descendant(
                                of: dialog,
                                matching: find.byType(DecoratedBox),
                              )
                              .first,
                        )
                        .decoration
                    as ShapeDecoration;
            surface = decoration.color!;
            expect(surface, AppTokens.of(tester.element(dialog)).surface);
          } else {
            surface = tester
                .widget<Material>(
                  find
                      .descendant(of: dialog, matching: find.byType(Material))
                      .first,
                )
                .color!;
            expect(
              surface,
              brightness == Brightness.dark ? Radix.slate2Dark : Radix.whiteA12,
            );
          }
          expect(
            surface.a,
            1,
            reason: 'The confirmation surface obscures the underlying page',
          );
          final title = find.text(switch (kind) {
            'cache' => '清除图片缓存？',
            'logout' => '退出当前账号？',
            _ => '清空运行日志？',
          });
          final style = isSheet
              ? tester.widget<Text>(title).style!
              : DefaultTextStyle.of(tester.element(title)).style;
          expect(style.fontSize, isSheet ? 18 : 17);
          expect(style.fontWeight, isSheet ? FontWeight.w700 : FontWeight.w600);
          expect(_contrast(style.color!, surface), greaterThanOrEqualTo(4.5));
          final rect = tester.getRect(dialog);
          expect(rect.left, greaterThanOrEqualTo(isSheet ? 8 : 0));
          expect(
            rect.right,
            lessThanOrEqualTo(
              tester.view.physicalSize.width - (isSheet ? 8 : 0),
            ),
          );
          if (isSheet) {
            final buttons = find.descendant(
              of: dialog,
              matching: find.byType(PressScale),
            );
            expect(buttons, findsNWidgets(2));
            for (final element in buttons.evaluate()) {
              final button = find.byWidget(element.widget);
              final text = find.descendant(
                of: button,
                matching: find.byType(Text),
              );
              final decoration =
                  tester
                          .widget<DecoratedBox>(
                            find
                                .descendant(
                                  of: button,
                                  matching: find.byWidgetPredicate(
                                    (widget) =>
                                        widget is DecoratedBox &&
                                        widget.decoration is BoxDecoration &&
                                        (widget.decoration as BoxDecoration)
                                                .color !=
                                            null,
                                  ),
                                )
                                .first,
                          )
                          .decoration
                      as BoxDecoration;
              final background = Color.alphaBlend(decoration.color!, surface);
              expect(
                tester.renderObject<RenderParagraph>(text).didExceedMaxLines,
                isFalse,
              );
              expect(
                tester.getSize(button).shortestSide,
                greaterThanOrEqualTo(44),
              );
              expect(
                _contrast(tester.widget<Text>(text).style!.color!, background),
                greaterThanOrEqualTo(4.5),
              );
            }
          } else {
            for (final element
                in find
                    .descendant(of: dialog, matching: find.byType(AppButton))
                    .evaluate()) {
              final button = element.widget as AppButton;
              final text = find.descendant(
                of: find.byWidget(button),
                matching: find.text(button.label),
              );
              expect(
                tester.renderObject<RenderParagraph>(text).didExceedMaxLines,
                isFalse,
              );
              expect(
                tester.getSize(find.byWidget(button)).shortestSide,
                greaterThanOrEqualTo(44),
              );
              expect(
                _contrast(tester.widget<Text>(text).style!.color!, surface),
                greaterThanOrEqualTo(4.5),
              );
              if (button.label != '取消') {
                expect(button.variant, AppButtonVariant.destructive);
              }
            }
          }
          expect(tester.takeException(), isNull);
          await _shot(tester, '$kind-${brightness.name}-$scale');
          await tester.tap(find.text('取消'));
          await tester.pumpAndSettle();
          expect(dialog, findsNothing);
          expect(chhSession.loggedIn, isTrue);
        });
      }
    }
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'directory keeps lazy rendering and collapse coordination scale $scale',
      (tester) async {
        tester.view.physicalSize = Size(scale == 2 ? 320 : 390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var loads = 0;
        await tester.pumpWidget(
          _app(
            ForumIndexView(
              loadForums: (_) async {
                loads++;
                return [
                  ForumCategory(
                    name: '交流区',
                    forums: List.generate(
                      1000,
                      (i) => Forum(fid: i + 1, name: '版块 $i'),
                    ),
                  ),
                ];
              },
            ),
            Brightness.light,
            scale,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('版块 ').evaluate().length, lessThan(40));
        expect(find.textContaining('版块 ').evaluate().length, greaterThan(0));
        final results = find.byType(CustomScrollView).last;
        await tester.drag(results, const Offset(0, -650));
        await tester.pumpAndSettle();
        final scroll = tester.widget<CustomScrollView>(results).controller!;
        expect(scroll.offset, greaterThan(0));
        final picker = find.byKey(const ValueKey('forum-directory-jump'));
        expect(picker.hitTestable(), findsOneWidget);
        scroll.jumpTo(0);
        await tester.pumpAndSettle();
        expect(picker.hitTestable(), findsNothing);
        expect(find.text('版块 0'), findsOneWidget);
        expect(find.textContaining('版块 ').evaluate().length, lessThan(40));
        expect(find.textContaining('版块 ').evaluate().length, greaterThan(0));
        expect(loads, 1);
        expect(tester.takeException(), isNull);
        await tester.drag(results, const Offset(0, 1000));
        await tester.pumpAndSettle();
        expect(loads, 2, reason: 'Pull to refresh is preserved');
      },
    );
  }
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'home forum section picker stays in compact bar on collapse scale $scale',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(scale == 2 ? 320 : 390, 844);
        tester.view.padding = const FakeViewPadding(top: 32, bottom: 24);
        tester.view.viewPadding = const FakeViewPadding(top: 32, bottom: 24);
        addTearDown(tester.view.reset);
        var loads = 0;
        await tester.pumpWidget(
          _app(
            HomePage(
              initialiseSession: () async {},
              screenBuilders: {
                AppDestination.feed: (_) => const Scaffold(body: Text('本地示例')),
                AppDestination.forums: (_) => ForumIndexView(
                  loadForums: (_) async {
                    loads++;
                    return [
                      ForumCategory(
                        name: '交流区',
                        forums: List.generate(
                          1000,
                          (i) => Forum(fid: i + 1, name: '版块 $i'),
                        ),
                      ),
                    ];
                  },
                ),
              },
            ),
            Brightness.light,
            scale,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(AppBottomNavigation),
            matching: find.text('版块'),
          ),
        );
        await tester.pumpAndSettle();
        final results = find.byType(CustomScrollView).last;
        final scroll = tester.widget<CustomScrollView>(results).controller!;
        final picker = find.byKey(const ValueKey('forum-directory-jump'));
        void expectBarSteady() {
          final rect = tester.getRect(picker);
          expect(rect.top, greaterThanOrEqualTo(32));
          expect(rect.bottom, lessThanOrEqualTo(32 + NavOverlay.barHeight));
        }

        expect(scroll.offset, 0);
        expectBarSteady();
        expect(picker.hitTestable(), findsNothing);
        expect(find.byType(AppBottomNavigation), findsOneWidget);
        expect(find.textContaining('版块 ').evaluate().length, lessThan(40));
        expect(find.textContaining('版块 ').evaluate().length, greaterThan(0));
        await _shot(tester, 'home-forum-initial-$scale');
        for (var i = 0; i < 4; i++) {
          final drag = await tester.startGesture(tester.getCenter(results));
          for (var step = 0; step < 4; step++) {
            await drag.moveBy(const Offset(0, -175));
            await tester.pump(const Duration(milliseconds: 16));
            expectBarSteady();
          }
          await drag.up();
          await tester.pumpAndSettle();
          expectBarSteady();
        }
        expect(scroll.offset, greaterThan(0));
        expect(picker.hitTestable(), findsOneWidget);
        await _shot(tester, 'home-forum-collapsed-$scale');
        await tester.tap(picker);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('picker-option-0')));
        await tester.pumpAndSettle();
        expect(find.text('版块 0'), findsOneWidget);
        expect(loads, 1);
        scroll.jumpTo(0);
        await tester.pumpAndSettle();
        await tester.drag(results, const Offset(0, 500));
        await tester.pumpAndSettle();
        expect(
          loads,
          2,
          reason:
              'One actual pull refresh issues exactly one extra catalog load',
        );
        expectBarSteady();
        expect(picker.hitTestable(), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
