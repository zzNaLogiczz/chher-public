import 'package:chh_app/design/theme.dart';
import 'package:chh_app/widgets/image_stack_mode_toggle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> mount(
  WidgetTester tester, {
  required bool expanded,
  bool reduced = false,
  VoidCallback? onPressed,
  double? progress,
}) => tester.pumpWidget(
  MaterialApp(
    theme: buildAppTheme(Brightness.light),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
      child: child!,
    ),
    home: Scaffold(
      body: Center(
        child: RepaintBoundary(
          key: const ValueKey('mode-icon-capture'),
          child: ImageStackModeToggle(
            expanded: expanded,
            progress: progress,
            total: 5,
            onPressed: onPressed ?? () {},
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('caption action keeps a 44dp target and full semantics', (
    tester,
  ) async {
    var taps = 0;
    await mount(tester, expanded: false, onPressed: () => taps++);
    await tester.pumpAndSettle();
    final target = tester.getRect(find.byType(ImageStackModeToggle));
    expect(target.height, greaterThanOrEqualTo(44));
    expect(target.width, greaterThanOrEqualTo(44));
    expect(find.text('展开全部'), findsOneWidget);
    expect(find.bySemanticsLabel('展开全部 5 张'), findsOneWidget);
    await tester.tap(find.byType(ImageStackModeToggle));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets(
    'collapse action retains its accessible label and responds once',
    (tester) async {
      var taps = 0;
      await mount(tester, expanded: true, onPressed: () => taps++);
      await tester.pumpAndSettle();
      expect(find.text('收起'), findsOneWidget);
      expect(find.bySemanticsLabel('收起为堆叠卡片'), findsOneWidget);
      await tester.tap(find.byType(ImageStackModeToggle));
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(tester.binding.hasScheduledFrame, isFalse);
    },
  );

  testWidgets('rapid mode reversal leaves the current action usable', (
    tester,
  ) async {
    await mount(tester, expanded: false);
    await tester.pumpAndSettle();
    await mount(tester, expanded: true);
    await tester.pump(const Duration(milliseconds: 90));
    await mount(tester, expanded: false);
    await tester.pumpAndSettle();
    expect(find.text('展开全部'), findsOneWidget);
    expect(find.text('收起'), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion changes the action directly and remains idle', (
    tester,
  ) async {
    await mount(tester, expanded: false, reduced: true);
    await tester.pumpAndSettle();
    await mount(tester, expanded: true, reduced: true);
    expect(find.text('收起'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
