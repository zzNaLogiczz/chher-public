import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chh_app/data/user_block_index.dart';
import 'package:chh_app/pages/blocked_users_page.dart';

void main() {
  testWidgets('narrow large text keeps identity and separate unblock usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final index = UserBlockIndex(null);
    await index.block(
      uid: '42',
      name: '非常长的用户昵称非常长的用户昵称',
      blockedAt: DateTime(2026, 11, 4),
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: BlockedUsersPage(index: index),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('2026-11-04 加入'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final unblock = find.byKey(const ValueKey('unblock-42'));
    expect(tester.getSize(unblock).height, greaterThanOrEqualTo(44));
    await tester.pumpWidget(const SizedBox());
    index.dispose();
  });
  testWidgets('empty list hides search', (tester) async {
    final index = UserBlockIndex(null);
    await tester.pumpWidget(MaterialApp(home: BlockedUsersPage(index: index)));
    await tester.pumpAndSettle();
    expect(find.text('黑名单为空'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.pumpWidget(const SizedBox());
    index.dispose();
  });
  testWidgets('search by UID, clear search and unblock reactively', (
    tester,
  ) async {
    final index = UserBlockIndex(null);
    await index.block(uid: '42', name: '示例作者');
    await tester.pumpWidget(MaterialApp(home: BlockedUsersPage(index: index)));
    await tester.pumpAndSettle();
    expect(find.text('示例作者'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '不存在');
    await tester.pumpAndSettle();
    expect(find.text('没有找到匹配的用户'), findsOneWidget);
    await tester.tap(find.text('清空搜索'));
    await tester.pumpAndSettle();
    expect(find.text('示例作者'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '42');
    await tester.pumpAndSettle();
    expect(find.text('示例作者'), findsOneWidget);
    final original = index.entries.single;
    expect(find.textContaining('UID 42'), findsOneWidget);
    await tester.tap(find.text('解除'));
    await tester.pumpAndSettle();
    expect(index.entries, isEmpty);
    expect(find.text('黑名单为空'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(index.entries.single.blockedAt, original.blockedAt);
    expect(find.text('示例作者'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    index.dispose();
  });
}
