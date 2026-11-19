import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/ui/message_filters.dart';
import 'package:chh_app/ui/picker.dart';
import 'package:chh_app/ui/sheet_scaffold.dart';
import 'package:chh_app/widgets/post_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder surface(Finder child) => find
    .descendant(
      of: child,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            (widget.decoration is ShapeDecoration ||
                widget.decoration is BoxDecoration &&
                    (widget.decoration as BoxDecoration).color != null &&
                    (widget.decoration as BoxDecoration).borderRadius != null),
      ),
    )
    .first;

double radius(WidgetTester tester, Finder surface) {
  final decoration = tester.widget<DecoratedBox>(surface).decoration;
  final BorderRadiusGeometry borderRadius;
  if (decoration is ShapeDecoration) {
    borderRadius = (decoration.shape as RoundedSuperellipseBorder).borderRadius;
  } else {
    borderRadius = (decoration as BoxDecoration).borderRadius!;
  }
  return borderRadius
      .resolve(TextDirection.ltr)
      .toRRect(Offset.zero & tester.getSize(surface))
      .scaleRadii()
      .tlRadiusX;
}

void main() {
  for (final style in AppearanceStyle.values) {
    for (final brightness in Brightness.values) {
      testWidgets(
        '$style $brightness sheet options are 44 capsules and choose once',
        (tester) async {
          final picked = <int>[];
          await tester.pumpWidget(
            MaterialApp(
              theme: buildAppTheme(brightness, style),
              home: Scaffold(
                body: Center(
                  child: PickerButton<int>(
                    sheetTitle: '排序方式',
                    value: 0,
                    options: const [
                      PickerOption(value: 0, label: '最新发布'),
                      PickerOption(value: 1, label: '回复最多'),
                    ],
                    onChanged: picked.add,
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('最新发布'));
          await tester.pumpAndSettle();
          for (var i = 0; i < 2; i++) {
            final tile = find.byKey(ValueKey('picker-option-$i'));
            expect(tester.getSize(tile).height, 44);
            expect(radius(tester, surface(tile)), 22);
          }
          await tester.tap(find.text('回复最多'));
          await tester.pumpAndSettle();
          expect(picked, [1]);
          expect(find.byType(AppSheetSurface), findsNothing);
          expect(tester.binding.transientCallbackCount, 0);
        },
      );

      testWidgets(
        '$style $brightness notice options are 44 capsules and keep view/type selection',
        (tester) async {
          final picked = <(int, String?)>[];
          await tester.pumpWidget(
            MaterialApp(
              theme: buildAppTheme(brightness, style),
              home: Scaffold(
                body: NoticeFilter(
                  view: 0,
                  type: null,
                  onChanged: (view, type) => picked.add((view, type)),
                ),
              ),
            ),
          );
          await tester.tap(find.text('全部'));
          await tester.pumpAndSettle();
          Future<void> checkOptions() async {
            final options = find.descendant(
              of: find.byType(AppSheetSurface),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is DecoratedBox &&
                    widget.decoration is BoxDecoration &&
                    (widget.decoration as BoxDecoration).borderRadius ==
                        BorderRadius.circular(AppRadii.full),
              ),
            );
            expect(options, findsWidgets);
            for (final element in options.evaluate()) {
              final option = find.byWidget(element.widget);
              expect(tester.getSize(option).height, 44);
              expect(radius(tester, option), 22);
            }
          }

          await checkOptions();
          await tester.tap(find.text('我的帖子'));
          await tester.pumpAndSettle();
          await checkOptions();
          await tester.tap(find.text('评分'));
          await tester.pumpAndSettle();
          expect(picked, [(1, null), (1, 'rate')]);
          expect(find.byType(AppSheetSurface), findsNothing);
          expect(tester.binding.transientCallbackCount, 0);
        },
      );

      testWidgets(
        '$style $brightness floor rating strip stays 26 high with radius 9',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: buildAppTheme(brightness, style),
              home: const Scaffold(
                body: FloorFeedback(
                  rating: PostRating(
                    summary: ['参与人数 1', '邪恶指数 +5'],
                    entries: [
                      RatingEntry(user: '本地评分者', score: '+5', reason: '样例附言'),
                    ],
                  ),
                ),
              ),
            ),
          );
          final strip = surface(find.byType(FloorFeedback));
          expect(tester.getSize(strip).height, 26);
          expect(radius(tester, strip), 9);
          expect(find.text('本地评分者'), findsOneWidget);
          expect(find.text('★ +5'), findsOneWidget);
          expect(find.text('样例附言'), findsNothing);
          await tester.tap(strip);
          await tester.pumpAndSettle();
          expect(find.text('+5 邪恶指数'), findsOneWidget);
          expect(find.text('样例附言'), findsOneWidget);
        },
      );
    }
  }

  testWidgets('picker preserves detail and wrapped labels as cards', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: PickerButton<int>(
            sheetTitle: '选择栏目',
            value: 0,
            options: const [
              PickerOption(value: 0, label: '短标题', detail: '真实说明'),
              PickerOption(value: 1, label: '另一栏目'),
              PickerOption(value: 2, label: '会在窄屏换行的栏目名称'),
              PickerOption(value: 3, label: '最后栏目'),
            ],
            onChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.tap(find.text('短标题'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      final tile = find.byKey(ValueKey('picker-option-$i'));
      expect(tester.getSize(tile).height, greaterThan(44));
      expect(radius(tester, surface(tile)), 18);
    }
    expect(find.text('真实说明'), findsOneWidget);
    expect(find.text('会在窄屏换行的栏目名称'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
