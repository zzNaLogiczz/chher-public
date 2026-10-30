import 'dart:ui' show Tristate;

import 'package:chh_app/design/theme.dart';
import 'package:chh_app/ui/picker.dart';
import 'package:chh_app/ui/segmented.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const three = [
  PickerOption(value: 0, label: '全部主题'),
  PickerOption(value: 1, label: '关注版块'),
  PickerOption(value: 2, label: '收藏'),
];

Widget app(Widget child, {double textScale = 1, bool reduced = false}) =>
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reduced,
          ),
          child: Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );

/// 受控分段:点击即更新 value,记录回调
Widget controlled(List<int> log, {double textScale = 1, bool reduced = false}) {
  var value = 0;
  return app(
    StatefulBuilder(
      builder: (context, setState) => AppSegmented<int>(
        options: three,
        value: value,
        fallbackTitle: '设置',
        onChanged: (v) {
          log.add(v);
          setState(() => value = v);
        },
      ),
    ),
    textScale: textScale,
    reduced: reduced,
  );
}

double thumbCenter(WidgetTester tester) =>
    tester.getCenter(find.byKey(AppSegmented.thumbKey)).dx;

double labelCenter(WidgetTester tester, String label) =>
    tester.getCenter(find.text(label)).dx;

void main() {
  testWidgets('thumb settles under the selected segment', (tester) async {
    final log = <int>[];
    await tester.pumpWidget(controlled(log));
    expect(thumbCenter(tester), closeTo(labelCenter(tester, '全部主题'), 1));
    await tester.tap(find.text('收藏'));
    await tester.pumpAndSettle();
    expect(thumbCenter(tester), closeTo(labelCenter(tester, '收藏'), 1));
    expect(log, [2]);
  });

  testWidgets('retargeting mid-slide ends on the last tap', (tester) async {
    final log = <int>[];
    await tester.pumpWidget(controlled(log));
    await tester.tap(find.text('关注版块'));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.text('收藏'));
    await tester.pumpAndSettle();
    expect(thumbCenter(tester), closeTo(labelCenter(tester, '收藏'), 1));
    expect(log, [1, 2]);
  });

  testWidgets('tapping the selected segment does nothing', (tester) async {
    final log = <int>[];
    await tester.pumpWidget(controlled(log));
    await tester.tap(find.text('全部主题'));
    await tester.pumpAndSettle();
    expect(log, isEmpty);
  });

  testWidgets('selection change clicks haptic', (tester) async {
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
    await tester.pumpWidget(controlled([]));
    await tester.tap(find.text('关注版块'));
    await tester.pumpAndSettle();
    expect(haptics, ['HapticFeedbackType.selectionClick']);
  });

  testWidgets('segments expose selected semantics', (tester) async {
    await tester.pumpWidget(controlled([]));
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('segment-0')))
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
    );
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('segment-2')))
          .flagsCollection
          .isSelected,
      Tristate.isFalse,
    );
  });

  testWidgets('overflowing labels at 2x text on 320dp fall back to a picker', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(controlled([], textScale: 2));
    expect(find.byType(PickerButton<int>), findsOneWidget);
    expect(find.byKey(AppSegmented.thumbKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact segments size to their labels', (tester) async {
    await tester.pumpWidget(
      app(
        Align(
          alignment: Alignment.centerRight,
          child: AppSegmented<int>(
            compact: true,
            options: const [
              PickerOption(value: 0, label: '最新'),
              PickerOption(value: 1, label: '热门'),
            ],
            value: 0,
            onChanged: (_) {},
          ),
        ),
      ),
    );
    final size = tester.getSize(find.byType(AppSegmented<int>));
    expect(size.height, 32);
    expect(size.width, lessThan(200));
  });

  testWidgets('reduced motion moves the thumb without animating', (
    tester,
  ) async {
    await tester.pumpWidget(controlled([], reduced: true));
    await tester.tap(find.text('收藏'));
    await tester.pump();
    expect(thumbCenter(tester), closeTo(labelCenter(tester, '收藏'), 1));
  });
}
