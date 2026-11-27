import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:chh_app/design/icons.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/design/typography.dart';
import 'package:chh_app/ui/chrome_button.dart';
import 'package:chh_app/ui/picker.dart';
import 'package:chh_app/ui/reading_bar.dart';
import 'package:chh_app/ui/segmented.dart';
import 'package:chh_app/widgets/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _capture = ValueKey('badge-pixel-capture');
const _fontFamily = 'BadgeTestRoboto';
const _pixelRatio = 3.0;

Rect _pixelBounds(ui.Image image, bool Function(int x, int y) includes) {
  var left = image.width;
  var right = 0;
  var top = image.height;
  var bottom = 0;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      if (!includes(x, y)) continue;
      left = math.min(left, x);
      right = math.max(right, x + 1);
      top = math.min(top, y);
      bottom = math.max(bottom, y + 1);
    }
  }
  final bounds = Rect.fromLTRB(
    left.toDouble(),
    top.toDouble(),
    right.toDouble(),
    bottom.toDouble(),
  );
  expect(bounds.isEmpty, isFalse);
  return bounds;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final config = File('.dart_tool/package_config.json').absolute;
    final packages =
        (jsonDecode(await config.readAsString()) as Map)['packages'] as List;
    final flutter = packages.cast<Map>().singleWhere(
      (package) => package['name'] == 'flutter',
    );
    final sdk = Directory.fromUri(
      config.uri.resolve(flutter['rootUri'] as String),
    ).parent.parent;
    final font = File.fromUri(
      sdk.uri.resolve('bin/cache/artifacts/material_fonts/Roboto-Bold.ttf'),
    );
    await (FontLoader(
      _fontFamily,
    )..addFont(font.readAsBytes().then(ByteData.sublistView))).load();
  });

  for (final scale in [1.0, 1.3]) {
    for (final count in [1, 8, 12, 99]) {
      testWidgets('CountBadge $count at $scale centers 3x ink and baseline', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(Brightness.light),
            home: Scaffold(
              body: Center(
                child: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: DefaultTextStyle.merge(
                    style: const TextStyle(fontFamily: _fontFamily),
                    child: RepaintBoundary(
                      key: _capture,
                      child: CountBadge(count: count),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final number = find.text('$count');
        final paragraph = tester.renderObject<RenderParagraph>(number);
        final baseline = paragraph.getDryBaseline(
          paragraph.constraints,
          TextBaseline.alphabetic,
        )!;
        final surface = tester.getRect(find.byKey(CountBadge.surfaceKey));
        expect(
          tester.getTopLeft(number).dy + baseline - surface.center.dy,
          closeTo(AppType.sizeCaption * scale * .36, .01),
        );
        expect(surface.height, closeTo(math.max(16, 14.4 * scale), .01));

        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(_capture),
        );
        final measurement = (await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: _pixelRatio);
          try {
            final bytes = (await image.toByteData())!;
            int channel(int x, int y, int channel) =>
                bytes.getUint8((y * image.width + x) * 4 + channel);
            bool opaque(int x, int y) => channel(x, y, 3) >= 128;
            final greenThreshold =
                (AppTokens.light.onAccent.g + AppTokens.light.red.g) * 127.5;
            final badge = _pixelBounds(image, opaque);
            final ink = _pixelBounds(
              image,
              (x, y) => opaque(x, y) && channel(x, y, 1) >= greenThreshold,
            );
            if (const bool.fromEnvironment('PHASE2_BADGE_CAPTURE')) {
              final png = (await image.toByteData(
                format: ui.ImageByteFormat.png,
              ))!;
              final file = File(
                'build/qa/perf-transition/phase2-badge-$count-$scale.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(png.buffer.asUint8List());
            }
            return (badge: badge, ink: ink);
          } finally {
            image.dispose();
          }
        }))!;
        final delta =
            (measurement.ink.center - measurement.badge.center) / _pixelRatio;
        debugPrint(
          'Badge $count at $scale: badge=${measurement.badge}, '
          'ink=${measurement.ink}, deltaDp=(${delta.dx}, ${delta.dy})',
        );
        expect(delta.dx.abs(), lessThanOrEqualTo(.5));
        expect(delta.dy.abs(), lessThanOrEqualTo(.5));
      });
    }
  }

  testWidgets('CountBadge fits top bar, messages and both reading tools', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final badge = find.byKey(CountBadge.surfaceKey);
    final chrome = find.byType(ChromeButton);
    final bottom = find.byType(AppBottomNavigation);
    Finder within(Finder parent) =>
        find.descendant(of: parent, matching: badge);

    for (final threadStyle in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: Scaffold(
              body: DefaultTextStyle.merge(
                style: const TextStyle(fontFamily: _fontFamily),
                child: Column(
                  children: [
                    const ChromeButton(
                      icon: AppIcons.notification,
                      tooltip: '浏览消息',
                      badgeCount: 99,
                    ),
                    AppSegmented<int>(
                      options: const [
                        PickerOption(value: 0, label: '提醒'),
                        PickerOption(value: 1, label: '私信'),
                      ],
                      value: 0,
                      onChanged: (_) {},
                      messageStyle: true,
                      onLac: true,
                      badgeCounts: const [12, 99],
                    ),
                    ReadingBar(
                      placeholder: '写回复…',
                      threadStyle: threadStyle,
                      onCompose: () {},
                      count: 99,
                      inComments: false,
                      onShowComments: () {},
                      onBackToTop: () {},
                    ),
                  ],
                ),
              ),
              bottomNavigationBar: AppBottomNavigation(
                current: AppDestination.messages,
                onNavigate: (_) {},
                messagesBadge: 99,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(badge, findsNWidgets(5));
      expect(tester.getSize(chrome), const Size.square(44));
      final chromeSurface = tester.getRect(find.byKey(ChromeButton.surfaceKey));
      final chromeBadge = tester.getRect(within(chrome));
      expect(chromeBadge.top, chromeSurface.top - 4);
      expect(chromeBadge.right, chromeSurface.right + 6);
      for (final (index, label) in ['提醒', '私信'].indexed) {
        final option = find.byKey(ValueKey('segment-$index'));
        final optionBadge = tester.getRect(within(option));
        expect(tester.getRect(option).contains(optionBadge.center), isTrue);
        expect(
          tester.getRect(find.text(label)).right,
          lessThan(optionBadge.left),
        );
      }
      final reading = find.byKey(ReadingBar.actionKey);
      final readingBadge = tester.getRect(within(reading));
      expect(readingBadge.top, tester.getRect(reading).top - 4);
      expect(readingBadge.right, lessThan(320));
      final bottomBadge = tester.getRect(within(bottom));
      expect(tester.getRect(bottom).contains(bottomBadge.topLeft), isTrue);
      expect(bottomBadge.bottom, lessThan(tester.getRect(find.text('消息')).top));
      expect(tester.takeException(), isNull);
    }
  });
}
