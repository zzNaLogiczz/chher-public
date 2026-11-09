import 'dart:io';
import 'dart:ui' as ui;
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/widgets/image_stack_mode_toggle.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
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

double leftX(WidgetTester tester) => tester
    .widget<Transform>(find.byKey(const ValueKey('image-stack-mode-card-0')))
    .transform
    .storage[12];

void checkCardBounds(WidgetTester tester) {
  final glyph = tester.renderObject<RenderBox>(
    find.byKey(ImageStackModeToggle.glyphKey),
  );
  final region = Offset.zero & glyph.size;
  for (final element
      in find
          .descendant(
            of: find.byKey(ImageStackModeToggle.glyphKey),
            matching: find.byType(RepaintBoundary),
          )
          .evaluate()) {
    final render = element.findRenderObject()! as RenderBox;
    final bounds = MatrixUtils.transformRect(
      render.getTransformTo(glyph),
      Offset.zero & render.size,
    );
    expect(bounds.left, greaterThanOrEqualTo(region.left));
    expect(bounds.right, lessThanOrEqualTo(region.right));
    expect(bounds.top, greaterThanOrEqualTo(region.top));
    expect(bounds.bottom, lessThanOrEqualTo(region.bottom));
  }
}

Future<void> capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('CHH_STACK_ICON_CAPTURE')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('mode-icon-capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 8);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('/tmp/chher-stack-mode-icon');
    await directory.create(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(png!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  testWidgets('small painted icon keeps 44dp touch and full semantics', (
    tester,
  ) async {
    var taps = 0;
    await mount(tester, expanded: false, onPressed: () => taps++);
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(ImageStackModeToggle)),
      const Size(44, 44),
    );
    expect(
      tester.getSize(find.byKey(ImageStackModeToggle.surfaceKey)),
      const Size(28, 28),
    );
    expect(
      tester.getSize(find.byKey(ImageStackModeToggle.glyphKey)),
      const Size(22, 22),
    );
    expect(find.byType(Text), findsNothing);
    expect(find.byType(Tooltip), findsNothing);
    expect(find.bySemanticsLabel('展开全部 5 张'), findsOneWidget);
    final target = tester.getRect(find.byType(ImageStackModeToggle));
    await tester.tapAt(target.topLeft + const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(taps, 1);
    checkCardBounds(tester);
  });

  testWidgets(
    'the same three outlines move through fan middle and vertical list',
    (tester) async {
      await mount(tester, expanded: false);
      await tester.pumpAndSettle();
      expect(leftX(tester), closeTo(-2.6, .001));
      checkCardBounds(tester);
      await capture(tester, 'fan');
      final originalCards = tester
          .elementList(find.byType(RepaintBoundary))
          .toList();
      await mount(tester, expanded: true);
      await tester.pump(const Duration(milliseconds: 70));
      final middle = leftX(tester);
      expect(middle, greaterThan(-2.6));
      expect(middle, lessThan(0));
      checkCardBounds(tester);
      await capture(tester, 'morph');
      expect(
        tester.elementList(find.byType(RepaintBoundary)).toList(),
        originalCards,
      );
      await tester.pumpAndSettle();
      expect(leftX(tester), closeTo(0, .001));
      expect(find.bySemanticsLabel('收起为堆叠卡片'), findsOneWidget);
      checkCardBounds(tester);
      final upper = tester.widget<Transform>(
        find.byKey(const ValueKey('image-stack-mode-card-0')),
      );
      final lower = tester.widget<Transform>(
        find.byKey(const ValueKey('image-stack-mode-card-2')),
      );
      expect(upper.transform.storage[13], closeTo(-6, .001));
      expect(lower.transform.storage[13], closeTo(6, .001));
      await capture(tester, 'row');
      expect(tester.binding.hasScheduledFrame, isFalse);
    },
  );

  testWidgets('rapid reversal continues from the in-flight position', (
    tester,
  ) async {
    await mount(tester, expanded: false);
    await tester.pumpAndSettle();
    await mount(tester, expanded: true);
    await tester.pump(const Duration(milliseconds: 90));
    final before = leftX(tester);
    await mount(tester, expanded: false);
    expect(leftX(tester), closeTo(before, .001));
    await tester.pumpAndSettle();
    expect(leftX(tester), closeTo(-2.6, .001));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('reduced motion uses a short smooth transition', (tester) async {
    await mount(tester, expanded: false, reduced: true);
    await tester.pumpAndSettle();
    await mount(tester, expanded: true, reduced: true);
    await tester.pump(const Duration(milliseconds: 60));
    expect(leftX(tester), greaterThan(-2.6));
    expect(leftX(tester), lessThan(0));
    checkCardBounds(tester);
    await tester.pump(const Duration(milliseconds: 100));
    expect(leftX(tester), closeTo(0, .001));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
  testWidgets('shared progress interpolates rectangle attributes exactly', (
    tester,
  ) async {
    await mount(tester, expanded: true, progress: .5);
    expect(leftX(tester), closeTo(-1.3, .001));
    expect(
      tester.getSize(find.byKey(const ValueKey('image-stack-mode-rect-0'))),
      const Size(12, 7),
    );
    final rectangles = tester
        .elementList(find.byType(RepaintBoundary))
        .toList();
    await mount(tester, expanded: true, progress: 1);
    expect(
      tester.getSize(find.byKey(const ValueKey('image-stack-mode-rect-0'))),
      const Size(16, 2),
    );
    expect(
      tester.elementList(find.byType(RepaintBoundary)).toList(),
      rectangles,
    );
    await mount(tester, expanded: false, progress: .5);
    expect(leftX(tester), closeTo(-1.3, .001));
    checkCardBounds(tester);
  });
}
