import 'dart:ui' show Tristate;
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/widgets/browse_thread_list.dart';
import 'package:chh_app/ui/plain_rows.dart';
import 'package:chh_app/ui/picker.dart';
import 'package:chh_app/ui/segmented.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget surface(Widget child) => MaterialApp(
  theme: buildAppTheme(Brightness.dark),
  home: MediaQuery(
    data: const MediaQueryData(textScaler: TextScaler.linear(2)),
    child: Scaffold(body: SizedBox(width: 320, child: child)),
  ),
);

void main() {
  testWidgets(
    'segmented selection has accessible state and never fires twice',
    (tester) async {
      final semantics = tester.ensureSemantics();

      var selected = 0;
      var changes = 0;
      await tester.pumpWidget(
        surface(
          StatefulBuilder(
            builder: (context, setState) => Column(
              children: [
                AppSegmented<int>(
                  options: const [
                    PickerOption(value: 0, label: '基本资料'),
                    PickerOption(value: 1, label: '论坛信息'),
                    PickerOption(value: 2, label: '隐私'),
                  ],
                  value: selected,
                  onChanged: (i) => setState(() {
                    selected = i;
                    changes++;
                  }),
                ),
              ],
            ),
          ),
        ),
      );
      // 2 倍字号 + 320dp:分段放不下,按规格降级为选择按钮,选中态在面板里
      expect(find.byType(PickerButton<int>), findsOneWidget);
      await tester.tap(find.text('基本资料'));
      await tester.pumpAndSettle();
      expect(
        tester
                .getSemantics(find.text('基本资料').last)
                .flagsCollection
                .isSelected ==
            Tristate.isTrue,
        isTrue,
      );
      await tester.tap(find.text('基本资料').last);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(changes, 0);
      await tester.tap(find.text('基本资料'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('隐私'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(changes, 1);
      semantics.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('large-text filters retain padding and 44dp touch targets', (
    tester,
  ) async {
    await tester.pumpWidget(
      surface(
        Column(
          children: [
            PickerButton<int>(
              sheetTitle: '选择分类',
              options: const [
                PickerOption(value: 1, label: '所有分类'),
                PickerOption(value: 2, label: '硬件讨论'),
              ],
              value: 1,
              onChanged: (_) {},
            ),
          ],
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(PickerButton<int>)).height,
      greaterThanOrEqualTo(44),
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is ListView && w.scrollDirection == Axis.horizontal,
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('short and long topic titles share the same reading edge', (
    tester,
  ) async {
    await tester.pumpWidget(
      surface(
        BrowseThreadList(
          loader: (_, {bool refresh = false}) async => const Paged(
            items: [
              ThreadSummary(
                tid: 1,
                title: '短标题',
                author: '甲',
                replies: 0,
                views: 0,
              ),
              ThreadSummary(
                tid: 2,
                title: '这是一条自然换行的较长标题',
                author: '乙',
                replies: 0,
                views: 0,
              ),
            ],
            page: PageInfo(current: 1, hasNext: false),
          ),
          itemBuilder: (_, thread) => ThreadRow(thread: thread),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('短标题')).dx,
      closeTo(tester.getTopLeft(find.text('这是一条自然换行的较长标题')).dx, .01),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('thread metadata wraps without overflowing narrow large text', (
    tester,
  ) async {
    await tester.pumpWidget(
      surface(
        const SingleChildScrollView(
          child: ThreadRow(
            thread: ThreadSummary(
              tid: 42,
              title: '装机记录',
              author: '社区用户',
              replies: 99999,
              views: 9999999,
              hasImages: true,
              lastPostTimeRaw: '2026-10-26 18:20:30',
            ),
            eyebrow: '电脑讨论',
          ),
        ),
      ),
    );
    expect(find.text('2026-10-26 18:20:30'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
