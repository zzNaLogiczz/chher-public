import 'package:chh_app/ui/balanced_title.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('D1 reflows an orphan without changing the line count', (
    tester,
  ) async {
    const title = '一二三四五六七八九十甲乙';
    const style = TextStyle(fontSize: 20);
    final width = (TextPainter(
      text: const TextSpan(text: '一二三四五六七八九十', style: style),
      textDirection: TextDirection.ltr,
    )..layout());
    final available = width.width + 1;
    width.dispose();

    Future<void> show(String title, {double scale = 1}) => tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Center(
            child: SizedBox(
              width: available,
              child: BalancedTitle(title, style: style),
            ),
          ),
        ),
      ),
    );

    await show(title);
    final balanced = tester.renderObject<RenderParagraph>(find.text(title));
    double lineAt(int offset) =>
        balanced.getOffsetForCaret(TextPosition(offset: offset), Rect.zero).dy;
    expect(lineAt(5), lineAt(0));
    expect(lineAt(6), greaterThan(lineAt(5)));
    expect(lineAt(title.length - 1), lineAt(6));
    expect(balanced.size.width, lessThan(available));

    await show(title, scale: 1.3);
    final resized = tester.renderObject<RenderParagraph>(find.text(title));
    expect(resized.size.width, available);

    const longerTail = '$title丙丁';
    await show(longerTail);
    expect(tester.getSize(find.text(longerTail)).width, available);
  });
}
