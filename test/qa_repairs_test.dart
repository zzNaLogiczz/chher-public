/// Offline regressions for the accepted 1.0.4 QA repairs.
library;

import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:chh_app/design/theme.dart';
import 'package:chh_app/di.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/forum_index_view.dart';
import 'package:chh_app/pages/log_page.dart';
import 'package:chh_app/pages/settings_page.dart';
import 'package:chh_app/ui/app_button.dart';
import 'package:chh_app/ui/grouped.dart';
import 'package:chh_app/ui/picker.dart';
import 'package:chh_app/ui/search_field.dart';
import 'package:chh_app/widgets/large_title_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/space_fixtures.dart';

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
              kind == 'logs'
                  ? const LogPage()
                  : SettingsPage(repository: FixtureSpace()),
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
          final dialog = find.byType(AlertDialog);
          final material = tester.widget<Material>(
            find.descendant(of: dialog, matching: find.byType(Material)).first,
          );
          expect(
            material.color!.a,
            1,
            reason: 'Actual M3 dialog surface must obscure the underlying page',
          );
          final title = find.text(switch (kind) {
            'cache' => '清除图片缓存？',
            'logout' => '退出当前账号？',
            _ => '清空运行日志？',
          });
          final style = DefaultTextStyle.of(tester.element(title)).style;
          expect(style.fontSize, 17);
          expect(style.fontWeight, FontWeight.w600);
          expect(
            _contrast(style.color!, material.color!),
            greaterThanOrEqualTo(4.5),
          );
          final rect = tester.getRect(dialog);
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(tester.view.physicalSize.width));
          for (final element
              in find
                  .descendant(of: dialog, matching: find.byType(AppButton))
                  .evaluate()) {
            final button = element.widget as AppButton;
            final text = find.descendant(
              of: find.byWidget(button),
              matching: find.text(button.label),
            );
            final paragraph = tester.renderObject<RenderParagraph>(text);
            expect(paragraph.didExceedMaxLines, isFalse);
            expect(
              tester.getSize(find.byWidget(button)).shortestSide,
              greaterThanOrEqualTo(44),
            );
            expect(
              _contrast(
                tester.widget<Text>(text).style!.color!,
                material.color!,
              ),
              greaterThanOrEqualTo(4.5),
            );
            if (button.label != '取消') {
              expect(
                button.variant,
                kind == 'cache'
                    ? AppButtonVariant.plain
                    : AppButtonVariant.destructive,
              );
            }
          }
          expect(tester.takeException(), isNull);
          await _shot(tester, '$kind-${brightness.name}-$scale');
          await tester.tap(find.text('取消'));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
          expect(chhSession.loggedIn, isTrue);
        });
      }
    }
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'nested directory keeps controls reachable after filtering, scrolling and resize scale $scale',
      (tester) async {
        tester.view.physicalSize = Size(scale == 2 ? 320 : 390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var loads = 0;
        await tester.pumpWidget(
          _app(
            LargeTitleScaffold(
              title: '版块',
              showBack: false,
              body: ForumIndexView(
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
            ),
            Brightness.light,
            scale,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(GroupedRow).evaluate().length, lessThan(40));
        final results = find.byType(CustomScrollView).last;
        await tester.drag(results, const Offset(0, -650));
        await tester.pumpAndSettle();
        final nested = tester.state<NestedScrollViewState>(
          find.byType(NestedScrollView),
        );
        expect(
          nested.outerController.offset,
          greaterThan(0),
          reason: 'Results retain nested title collapse coordination',
        );
        final field = find.byType(EditableText);
        expect(
          field.hitTestable(),
          findsOneWidget,
          reason: 'Filter must stay available while only results scroll',
        );
        await tester.tap(field);
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();
        await tester.enterText(field, 'no-match');
        await tester.pumpAndSettle();
        expect(find.text('没有找到相关版块'), findsOneWidget);
        final editable = tester.widget<EditableText>(field);
        editable.controller.selection = const TextSelection(
          baseOffset: 1,
          extentOffset: 4,
        );
        for (final height in [700.0, 844.0]) {
          tester.view.physicalSize = Size(
            tester.view.physicalSize.width,
            height,
          );
          await tester.pumpAndSettle();
          final clear = find.byType(SearchClearButton);
          expect(field.hitTestable(), findsOneWidget);
          expect(clear.hitTestable(), findsOneWidget);
          final rect = tester.getRect(clear);
          expect(rect.bottom, lessThan(height - 300));
          expect(rect.shortestSide, greaterThanOrEqualTo(44));
          expect(tester.widget<EditableText>(field).focusNode.hasFocus, isTrue);
          expect(
            tester.widget<EditableText>(field).controller.selection,
            const TextSelection(baseOffset: 1, extentOffset: 4),
          );
          final render = tester.state<EditableTextState>(field).renderEditable;
          expect(
            render.size.height,
            greaterThanOrEqualTo(render.preferredLineHeight),
          );
        }
        await _shot(tester, 'forum-empty-$scale');
        await tester.tap(find.byType(SearchClearButton));
        await tester.pumpAndSettle();
        expect(tester.widget<EditableText>(field).controller.text, isEmpty);
        expect(tester.widget<EditableText>(field).focusNode.hasFocus, isTrue);
        expect(find.text('版块 0'), findsOneWidget);
        expect(find.byType(GroupedRow).evaluate().length, lessThan(40));
        expect(loads, 1);
        expect(find.byType(PickerButton<int>).hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _shot(tester, 'forum-restored-$scale');
        tester.view.viewInsets = FakeViewPadding.zero;
        await tester.pumpAndSettle();
        await tester.tap(find.byType(PickerButton<int>));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('picker-option-1')));
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<PickerButton<int>>(find.byType(PickerButton<int>))
              .value,
          0,
        );
        expect(loads, 1);
        await tester.tap(field);
        await tester.enterText(field, 'no-match');
        await tester.pumpAndSettle();
        await tester.tap(find.byType(SearchClearButton));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<PickerButton<int>>(find.byType(PickerButton<int>))
              .value,
          0,
        );
        expect(find.text('版块 0'), findsOneWidget);
        expect(loads, 1);
        await tester.drag(results, const Offset(0, 1000));
        await tester.pumpAndSettle();
        expect(loads, 2, reason: 'Pull to refresh is preserved');
      },
    );
  }
}
