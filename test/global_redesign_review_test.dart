import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/ui/bottom_bar.dart';
import 'package:chh_app/ui/grouped.dart';
import 'package:chh_app/ui/plain_rows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  return ((a > b ? a : b) + .05) / ((a > b ? b : a) + .05);
}

void main() {
  for (final style in AppearanceStyle.values) {
    for (final brightness in Brightness.values) {
      final label = '${style.name} ${brightness.name}';
      test('$label essential text and action colors remain readable', () {
        final t = tokensFor(brightness, style);
        for (final background in [t.bg, t.grouped, t.surface]) {
          for (final foreground in [t.text, t.text2]) {
            expect(contrast(foreground, background), greaterThanOrEqualTo(4.5));
          }
        }
        expect(contrast(t.accent, t.surface), greaterThanOrEqualTo(4.5));
        expect(contrast(t.onAccent, t.btnTop), greaterThanOrEqualTo(4.5));
      });

      testWidgets('$label shared rows keep actions without separator strokes', (
        tester,
      ) async {
        var taps = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(brightness, style),
            home: Scaffold(
              body: Column(
                children: [
                  GroupedSection(
                    header: '账户',
                    children: [
                      GroupedRow(title: '设置', onTap: () => taps++),
                      const GroupedRow(title: '状态', value: '已登录'),
                    ],
                  ),
                  PlainRow(onTap: () => taps++, child: const Text('帖子')),
                ],
              ),
              bottomNavigationBar: const BottomBar(child: Text('底部操作')),
            ),
          ),
        );
        expect(find.byType(Divider), findsNothing);
        expect(find.byType(VerticalDivider), findsNothing);
        for (final widget in tester.widgetList<DecoratedBox>(
          find.byType(DecoratedBox),
        )) {
          if (widget.decoration case BoxDecoration(:final border)) {
            expect(border, isNull);
          }
        }
        await tester.tap(find.text('设置'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('帖子'));
        await tester.pumpAndSettle();
        expect(taps, 2);
        expect(find.text('已登录'), findsOneWidget);
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
