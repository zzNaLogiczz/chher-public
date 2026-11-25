import 'package:chh_app/data/user_block_index.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/ui/user_block_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _source = BlockedUserSource(
  tid: 120,
  pid: 730,
  floor: 37,
  title: '本地示例帖子',
  excerpt: '那一楼的原文',
);

Future<void> _show(
  WidgetTester tester,
  UserBlockIndex index, {
  BlockedUserSource? source,
  bool reduced = false,
  VoidCallback? onOpenSource,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => toggleUserBlock(
              context,
              uid: '42',
              name: '示例作者',
              index: index,
              src: source,
              onOpenSource: onOpenSource,
            ),
            child: const Text('打开确认层'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开确认层'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('确认前不弹键盘，追加理由去重，确认保存来源与备注后可撤销', (tester) async {
    final index = UserBlockIndex.forTesting(null);
    addTearDown(index.dispose);
    await _show(tester, index, source: _source);

    final field = find.byType(TextField);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isFalse);
    expect(index.entryFor('42'), isNull);
    expect(find.text('备注（可选）'), findsOneWidget);
    expect(find.textContaining('UID 42 · '), findsOneWidget);
    expect(find.text('来自《本地示例帖子》'), findsOneWidget);
    expect(find.text('#37'), findsOneWidget);

    await tester.tap(find.text('广告'));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isFalse);
    await tester.enterText(field, '自己的备注，广告');
    await tester.tap(find.text('引战'));
    await tester.pump();
    await tester.tap(find.text('广告'));
    await tester.tap(find.text('引战'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, '自己的备注，广告，引战');
    final confirm = find.widgetWithText(UserBlockSheetButton, '加入黑名单');
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    final entry = index.entryFor('42')!;
    expect(entry.note, '自己的备注，广告，引战');
    expect(entry.src?.tid, 120);
    expect(entry.src?.pid, 730);
    expect(entry.src?.floor, 37);
    expect(entry.src?.title, '本地示例帖子');
    expect(entry.src?.excerpt, '那一楼的原文');
    expect(find.text('已加入黑名单'), findsOneWidget);
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(index.entryFor('42'), isNull);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('无来源省略来源行，备注限制 200 字，理由不挤掉已有内容', (tester) async {
    final index = UserBlockIndex.forTesting(null);
    addTearDown(index.dispose);
    await _show(tester, index, reduced: true);
    expect(find.textContaining('来自《'), findsNothing);

    final field = find.byType(TextField);
    final full = '甲' * 200;
    await tester.enterText(field, '$full乙');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, full);
    await tester.tap(find.text('交易纠纷'));
    final confirm = find.widgetWithText(UserBlockSheetButton, '加入黑名单');
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(index.entryFor('42')?.note, full);
    expect(index.entryFor('42')?.src, isNull);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('确认前可以回到来源楼且不写入黑名单', (tester) async {
    final index = UserBlockIndex.forTesting(null);
    addTearDown(index.dispose);
    var jumps = 0;
    await _show(tester, index, source: _source, onOpenSource: () => jumps++);
    await tester.tap(find.text('来自《本地示例帖子》'));
    await tester.pumpAndSettle();
    expect(jumps, 1);
    expect(index.entryFor('42'), isNull);
    expect(find.byType(UserBlockSheetIdentity), findsNothing);
  });

  testWidgets('窄屏键盘可输入、清空并取消备注', (tester) async {
    final index = UserBlockIndex.forTesting(null);
    addTearDown(index.dispose);
    addTearDown(tester.view.resetViewInsets);
    await _show(tester, index, source: _source, reduced: true);
    tester.view.physicalSize = const Size(320, 680);
    final field = find.byType(TextField);
    await tester.pumpAndSettle();
    await tester.tap(field);
    tester.view.viewInsets = const FakeViewPadding(bottom: 290);
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isTrue);
    expect(tester.getBottomLeft(field).dy, lessThanOrEqualTo(680 - 290));
    expect(field.hitTestable(), findsOneWidget);
    await tester.enterText(field, '测');
    expect(tester.widget<TextField>(field).controller!.text, '测');
    await tester.enterText(field, '');
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    await tester.binding.handlePopRoute();
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
    expect(find.byType(UserBlockSheetIdentity), findsNothing);
    expect(index.entries, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('确认层打开后切账号，旧确认不修改新账号', (tester) async {
    final index = UserBlockIndex.forTesting(null);
    addTearDown(index.dispose);
    await _show(tester, index, reduced: true);

    await index.setUid('901');
    await tester.pumpAndSettle();

    expect(find.byType(UserBlockSheetIdentity), findsNothing);
    expect(index.entries, isEmpty);
    expect(find.text('撤销'), findsNothing);
  });

  testWidgets('切账号后旧账号的撤销不会修改新账号同一黑名单条目', (tester) async {
    final index = UserBlockIndex.forTesting(null);
    addTearDown(index.dispose);
    await _show(tester, index, reduced: true);
    await tester.tap(find.widgetWithText(UserBlockSheetButton, '加入黑名单'));
    await tester.pumpAndSettle();
    expect(find.text('撤销'), findsOneWidget);

    await index.setUid('901');
    await index.block(uid: '42', name: '另一个账号的记录');
    await tester.pumpAndSettle();

    expect(find.text('撤销'), findsNothing);
    expect(index.entryFor('42')?.name, '另一个账号的记录');
    await tester.pump(const Duration(seconds: 5));
  });
}
