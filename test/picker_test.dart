import 'dart:io';
import 'package:chh_app/design/motion.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/ui/picker.dart';
import 'package:chh_app/ui/sheet_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui' show Tristate;
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child) => MaterialApp(
  theme: buildAppTheme(Brightness.light),
  home: Scaffold(body: Center(child: child)),
);

final opts = [
  for (final (v, l) in [(0, '全部分区'), (1, '互动区'), (2, '分享区')])
    PickerOption(value: v, label: l, detail: v == 0 ? null : '3 个版块'),
];

List<Object?> recordHaptics(WidgetTester tester) {
  final haptics = <Object?>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments);
      return null;
    },
  );
  return haptics;
}

void main() {
  sheetTests();
  testWidgets('a wide option spans the row and paired tiles share one height', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        PickerButton<int>(
          sheetTitle: '选择分区',
          options: const [
            PickerOption(value: -1, label: '全部分区', detail: '9 个版块', wide: true),
            PickerOption(value: 0, label: '互动区', detail: '3 个版块'),
            PickerOption(value: 1, label: '分享区'),
            PickerOption(value: 2, label: '硬件区', detail: '3 个版块'),
            PickerOption(value: 3, label: '生活区', detail: '3 个版块'),
          ],
          value: -1,
          onChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.text('全部分区'));
    await tester.pumpAndSettle();
    Rect tile(int i) =>
        tester.getRect(find.byKey(ValueKey('picker-option-$i')).first);
    final all = tile(0);
    final row1 = [tile(1), tile(2)];
    final row2 = [tile(3), tile(4)];
    // "全部分区"独占一行,与下方两列的总宽一致
    expect(all.width, closeTo(row1[1].right - row1[0].left, .5));
    for (final row in [row1, row2]) {
      expect(row[0].width, closeTo(row[1].width, .5));
      expect(row[0].top, row[1].top);
      // 一侧没有说明行也不会比另一侧矮
      expect(row[0].height, closeTo(row[1].height, .5));
    }
    expect(row1[0].width, closeTo(row2[0].width, .5));
    expect(tester.takeException(), isNull);
  });

  test('sheet spring curve starts at 0, ends at 1 and overshoots lightly', () {
    final curve = AppMotion.curveOf(AppMotion.sheet);
    expect(curve.transform(0), 0);
    expect(curve.transform(1), 1);
    final peak = [
      for (var i = 1; i < 100; i++) curve.transform(i / 100),
    ].reduce((a, b) => a > b ? a : b);
    expect(peak, greaterThan(1));
    expect(peak, lessThan(1.02));
  });

  testWidgets('picker opens a sheet and marks the current option selected', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        PickerButton<int>(
          sheetTitle: '选择分区',
          options: opts,
          value: 0,
          onChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.text('全部分区'));
    await tester.pumpAndSettle();
    expect(find.text('选择分区'), findsOneWidget);
    expect(find.text('3 个版块'), findsNWidgets(2));
    final selected = tester.getSemantics(
      find.ancestor(
        of: find.text('全部分区').last,
        matching: find.byKey(const ValueKey('picker-option-0')),
      ),
    );
    expect(selected.flagsCollection.isSelected, Tristate.isTrue);
    final other = tester.getSemantics(
      find.byKey(const ValueKey('picker-option-1')),
    );
    expect(other.flagsCollection.isSelected, Tristate.isFalse);
  });

  testWidgets('choosing a null option is reported, not taken as dismissal', (
    tester,
  ) async {
    final reported = <String?>[];
    await tester.pumpWidget(
      app(
        PickerButton<String?>(
          sheetTitle: '提醒子类型',
          options: const [
            PickerOption(value: null, label: '全部类型'),
            PickerOption(value: 'pcomment', label: '点评'),
          ],
          value: 'pcomment',
          onChanged: reported.add,
        ),
      ),
    );
    await tester.tap(find.text('点评'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部类型'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(reported, [null]);
  });

  testWidgets('a value outside the options shows the placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        PickerButton<int?>(
          sheetTitle: '选择分类',
          placeholder: '选择分类',
          options: const [
            PickerOption(value: 1010, label: 'ITX'),
            PickerOption(value: 1011, label: '水冷'),
          ],
          value: null,
          onChanged: (_) {},
        ),
      ),
    );
    expect(find.text('选择分类'), findsOneWidget);
    expect(find.text('ITX'), findsNothing);
  });

  testWidgets('choosing reports once, clicks haptic and closes after 200ms', (
    tester,
  ) async {
    final haptics = recordHaptics(tester);
    final picked = <int>[];
    var value = 0;
    await tester.pumpWidget(
      app(
        StatefulBuilder(
          builder: (context, setState) => PickerButton<int>(
            sheetTitle: '选择分区',
            options: opts,
            value: value,
            onChanged: (v) {
              picked.add(v);
              setState(() => value = v);
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('全部分区'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('互动区'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('互动区').last, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 130));
    expect(find.text('选择分区'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('选择分区'), findsNothing);
    expect(picked, [1]);
    expect(haptics, ['HapticFeedbackType.selectionClick']);
    expect(find.text('互动区'), findsOneWidget);
  });

  testWidgets('choosing the current value does not report a change', (
    tester,
  ) async {
    final picked = <int>[];
    await tester.pumpWidget(
      app(
        PickerButton<int>(
          sheetTitle: '选择分区',
          options: opts,
          value: 0,
          onChanged: picked.add,
        ),
      ),
    );
    await tester.tap(find.text('全部分区'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部分区').last);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('选择分区'), findsNothing);
    expect(picked, isEmpty);
  });

  testWidgets('sheet scaffold shows title, count, context line and closes', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showAppSheet<void>(
              context,
              builder: (_) => const SheetScaffold(
                title: '评论',
                count: 23,
                contextLine: '示例硬件评测',
                body: SizedBox(height: 120),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('评论'), findsOneWidget);
    expect(find.text('23'), findsOneWidget);
    final context = tester.widget<Text>(
      find.text('示例硬件评测'),
    );
    expect(context.maxLines, 1);
    expect(context.overflow, TextOverflow.ellipsis);
    expect(context.style!.color, AppTokens.light.text3);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('评论'), findsNothing);
  });
}

void sheetTests() {
  test('no modal bottom sheets remain outside showAppSheet', () {
    final offenders = <String>[];
    for (final f in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.endsWith('sheet_scaffold.dart')) {
        continue;
      }
      if (f.readAsStringSync().contains('showModalBottomSheet')) {
        offenders.add(f.path);
      }
    }
    expect(offenders, isEmpty);
  });

  testWidgets('sheet header keeps a custom close label and grabber key', (
    tester,
  ) async {
    var closed = 0;
    await tester.pumpWidget(
      app(
        SheetHeader(
          title: '回复',
          contextLine: '已加载 2 条回复',
          closeTooltip: '关闭回复',
          grabberKey: const ValueKey('grip'),
          onClose: () => closed++,
        ),
      ),
    );
    expect(find.byKey(const ValueKey('grip')), findsOneWidget);
    expect(find.byTooltip('刷新评论'), findsNothing);
    await tester.tap(find.byTooltip('关闭回复'));
    expect(closed, 1);
    final line = tester.widget<Text>(find.text('已加载 2 条回复'));
    expect(line.maxLines, 1);
  });

  Future<void> openShortSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showAppSheet<void>(
              context,
              builder: (_) =>
                  const SheetScaffold(title: '选择分区', body: Text('说明')),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  TextStyle paintedStyle(WidgetTester tester, String text) => tester
      .widget<RichText>(
        find.descendant(of: find.text(text), matching: find.byType(RichText)),
      )
      .text
      .style!;

  testWidgets('sheet text never falls back to the debug underline style', (
    tester,
  ) async {
    await openShortSheet(tester);
    for (final text in ['选择分区', '说明']) {
      final style = paintedStyle(tester, text);
      expect(style.decoration ?? TextDecoration.none, TextDecoration.none);
    }
  });

  testWidgets('sheet close button stays at the right edge for short titles', (
    tester,
  ) async {
    await openShortSheet(tester);
    final surfaceRight = tester.getTopRight(find.byType(AppSheetSurface)).dx;
    final closeRight = tester.getTopRight(find.byTooltip('关闭')).dx;
    expect(closeRight, moreOrLessEquals(surfaceRight - 8, epsilon: .5));
  });

  testWidgets('sheet surface paints no blurred shadow over the scrim', (
    tester,
  ) async {
    await openShortSheet(tester);
    final surface = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(AppSheetSurface),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    final decoration = surface.decoration;
    final shadows = decoration is ShapeDecoration
        ? decoration.shadows
        : (decoration as BoxDecoration).boxShadow;
    expect(shadows ?? const [], isEmpty);
  });
}
