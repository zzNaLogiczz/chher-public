import 'package:chh_app/data/history_index.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/pages/history_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

final _thread = find.byKey(const ValueKey('thread:1'));
final _article = find.byKey(const ValueKey('article:2'));
final _clear = find.bySemanticsLabel('清空浏览历史');
final _delete = find.text('删除');

HistoryIndex _fixture() {
  final index = HistoryIndex(null);
  addTearDown(index.dispose);
  final now = DateTime.now();
  index.record(
    type: HistoryType.thread,
    id: 3,
    title: '外设体验',
    author: '网友',
    at: DateTime(now.year - 1, 3, 2, 8, 6),
  );
  index.record(
    type: HistoryType.article,
    id: 2,
    title: '周末装机记录',
    author: '文章作者',
    column: '电脑硬件',
    at: DateTime(now.year, now.month, now.day - 1, 15, 9),
  );
  index.record(
    type: HistoryType.thread,
    id: 1,
    title: 'NAS 家庭网络',
    author: '楼主甲',
    fid: 22,
    forumName: '电脑讨论',
    at: DateTime(now.year, now.month, now.day, 10, 3),
  );
  return index;
}

Future<void> _mount(
  WidgetTester tester,
  HistoryIndex index, {
  bool reduced = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      home: HistoryPage(index: index),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
        child: child!,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _expireToast(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 7));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('empty history shows only its message and navigation', (
    tester,
  ) async {
    final index = HistoryIndex(null);
    addTearDown(index.dispose);
    await _mount(tester, index);
    expect(find.byTooltip('返回'), findsOneWidget);
    expect(find.text('浏览历史').hitTestable(), findsOneWidget);
    expect(find.text('还没有浏览记录'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('清空'), findsNothing);
  });

  testWidgets('groups local dates and filters only on the title', (
    tester,
  ) async {
    final index = _fixture();
    await _mount(tester, index);
    expect(_clear, findsOneWidget);
    expect(find.text('今天'), findsOneWidget);
    expect(find.text('昨天'), findsOneWidget);
    expect(find.text('3月2日'), findsOneWidget);
    expect(find.text('电脑讨论 · 楼主甲'), findsOneWidget);
    expect(find.text(' · 10:03'), findsOneWidget);
    expect(find.text('文章'), findsOneWidget);
    expect(find.text(' · 电脑硬件'), findsOneWidget);
    expect(find.text(' · 15:09'), findsOneWidget);
    final threadSemantics = tester.getSemantics(
      find.bySemanticsLabel('帖子，NAS 家庭网络，电脑讨论，楼主甲，10:03'),
    );
    expect(
      threadSemantics.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
    );
    expect(
      threadSemantics.getSemanticsData().customSemanticsActionIds,
      contains(
        CustomSemanticsAction.getIdentifier(
          const CustomSemanticsAction(label: '删除'),
        ),
      ),
    );

    final search = find.byType(TextField);
    await tester.tap(search);
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.enterText(search, ' nas ');
    await tester.pumpAndSettle();
    expect(_thread, findsOneWidget);
    expect(_article, findsNothing);
    expect(find.text('昨天'), findsNothing);

    await tester.enterText(search, '楼主甲');
    await tester.pumpAndSettle();
    expect(_thread, findsNothing);
    expect(find.text('没有找到'), findsOneWidget);
    await tester.tap(find.text('清空搜索'));
    await tester.pumpAndSettle();
    expect(_thread, findsOneWidget);
    expect(_article, findsOneWidget);
    expect(tester.widget<TextField>(search).controller!.text, isEmpty);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
  }, semanticsEnabled: true);

  testWidgets('swipe follows left, springs closed and opens on a short fling', (
    tester,
  ) async {
    await _mount(tester, _fixture());
    final title = find.text('NAS 家庭网络');
    final resting = tester.getTopLeft(title);
    expect(_delete, findsNothing);

    final right = await tester.startGesture(tester.getCenter(_thread));
    await right.moveBy(const Offset(32, 0));
    await tester.pump();
    expect(_delete, findsNothing);
    expect(tester.getTopLeft(title), resting);
    await right.up();

    final drag = await tester.startGesture(tester.getCenter(_thread));
    await drag.moveBy(const Offset(-30, 0));
    await tester.pump();
    expect(_delete, findsOneWidget);
    expect(tester.getTopLeft(title).dx, closeTo(resting.dx - 30, .1));
    await drag.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      tester.getTopLeft(title).dx,
      inExclusiveRange(resting.dx - 30, resting.dx),
    );
    await tester.pumpAndSettle();
    expect(_delete, findsNothing);
    expect(tester.getTopLeft(title), resting);

    Future<void> flick(double step) async {
      final gesture = await tester.startGesture(tester.getCenter(_thread));
      for (var i = 1; i <= 6; i++) {
        await gesture.moveBy(
          Offset(step, 0),
          timeStamp: Duration(milliseconds: 7 * i),
        );
      }
      await gesture.up(timeStamp: const Duration(milliseconds: 45));
    }

    await flick(-7);
    await tester.pumpAndSettle();
    expect(_delete.hitTestable(), findsOneWidget);
    expect(tester.getTopLeft(title).dx, closeTo(resting.dx - 88, .1));
    await flick(7);
    await tester.pumpAndSettle();
    expect(_delete, findsNothing);
    expect(tester.getTopLeft(title), resting);
  });

  testWidgets('delete folds the row and Undo restores its previous order', (
    tester,
  ) async {
    final index = _fixture();
    await _mount(tester, index);
    final height = tester.getSize(_thread).height;
    await tester.drag(_thread, const Offset(-90, 0));
    await tester.pumpAndSettle();
    await tester.tap(_delete);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getSize(_thread).height, inExclusiveRange(0, height));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(_thread, findsNothing);
    expect(find.text('已删除'), findsOneWidget);
    expect(index.all.map((entry) => entry.id), [2, 3]);
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(_thread, findsOneWidget);
    expect(_delete, findsNothing);
    expect(index.all.map((entry) => entry.id), [1, 2, 3]);
    await _expireToast(tester);
  });

  for (final reduced in [false, true]) {
    testWidgets(
      'clearing confirms, hides controls and supports Undo ($reduced)',
      (tester) async {
        final index = _fixture();
        await _mount(tester, index, reduced: reduced);
        await tester.tap(_clear);
        await tester.pumpAndSettle();
        expect(find.text('清空浏览历史？'), findsOneWidget);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(index.all.length, 3);

        await tester.tap(_clear);
        await tester.pumpAndSettle();
        await tester.tap(find.text('清空').hitTestable().last);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 650));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(index.all, isEmpty);
        expect(find.text('还没有浏览记录'), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
        expect(_clear, findsNothing);
        expect(find.text('已清空'), findsOneWidget);
        await tester.tap(find.text('撤销'));
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsOneWidget);
        expect(_clear, findsOneWidget);
        expect(index.all.map((entry) => entry.id), [1, 2, 3]);
        await _expireToast(tester);
      },
      semanticsEnabled: true,
    );
  }

  testWidgets('reduced motion reveals and removes without moving the row', (
    tester,
  ) async {
    final index = _fixture();
    await _mount(tester, index, reduced: true);
    final title = find.text('NAS 家庭网络');
    final resting = tester.getTopLeft(title);
    final height = tester.getSize(_thread).height;
    await tester.drag(_thread, const Offset(-90, 0));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(title), resting);
    expect(_delete.hitTestable(), findsOneWidget);
    await tester.tap(_delete);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 75));
    expect(tester.getSize(_thread).height, height);
    await tester.pumpAndSettle();
    expect(_thread, findsNothing);
    expect(index.all.map((entry) => entry.id), [2, 3]);
    await _expireToast(tester);
  });
}
