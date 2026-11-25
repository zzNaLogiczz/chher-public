import 'dart:async';

import 'package:chh_app/data/follow_index.dart';
import 'package:chh_app/data/user_block_index.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/di.dart';
import 'package:chh_app/pages/user_drawer.dart';
import 'package:chh_app/pages/user_page.dart';
import 'package:chh_app/parser/header_parser.dart';
import 'package:chh_app/ui/user_block_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/space_fixtures.dart';

Widget _app(Widget page) =>
    MaterialApp(theme: buildAppTheme(Brightness.light), home: page);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('chh/update'),
          (_) async => null,
        );
  });

  testWidgets('资料页拉黑取消关注，撤销保留联动结果，切换账号与登出后刷新', (tester) async {
    await followIndex.setUid('900');
    await userBlockIndex.setUid('900');
    await tester.pumpWidget(
      _app(UserPage(uid: '42', repository: FixtureSpace())),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getCenter(find.text('关注')).dy,
      tester.getCenter(find.text('加入黑名单')).dy,
    );
    await tester.tap(find.text('关注'));
    await tester.pumpAndSettle();
    expect(followIndex.isFollowed('42'), isTrue);
    expect(find.text('已关注'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text('已关注'));
    final cancelledToast = find.text('已取消关注');
    for (var i = 0; i < 50 && cancelledToast.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(followIndex.isFollowed('42'), isFalse);
    expect(find.text('已取消关注'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text('关注'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text('加入黑名单'));
    await tester.pumpAndSettle();
    expect(find.text('同时取消关注'), findsOneWidget);
    await tester.tap(find.widgetWithText(UserBlockSheetButton, '加入黑名单'));
    await tester.pumpAndSettle();
    expect(followIndex.isFollowed('42'), isFalse);
    expect(find.text('关注'), findsNothing);
    expect(find.text('解除黑名单'), findsOneWidget);
    unawaited(userBlockIndex.updateNote('42', '本地备注'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('本地备注')).dy,
      greaterThan(tester.getBottomLeft(find.text('已加入黑名单')).dy),
    );

    await tester.tap(find.text('解除黑名单'));
    await tester.pumpAndSettle();
    expect(userBlockIndex.isBlocked('42'), isFalse);
    expect(followIndex.isFollowed('42'), isFalse);
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(userBlockIndex.entryFor('42')?.note, '本地备注');
    expect(followIndex.isFollowed('42'), isFalse);
    await tester.pump(const Duration(seconds: 5));

    await followIndex.setUid('902');
    await userBlockIndex.setUid('902');
    await tester.pumpAndSettle();
    expect(find.text('解除黑名单'), findsNothing);
    expect(find.text('加入黑名单'), findsOneWidget);

    await followIndex.setUid('900');
    await userBlockIndex.setUid('900');
    await tester.pumpAndSettle();
    expect(find.text('解除黑名单'), findsOneWidget);

    await followIndex.setUid(null);
    await userBlockIndex.setUid(null);
    await tester.pumpAndSettle();
    expect(find.text('解除黑名单'), findsNothing);
    await tester.tap(find.text('关注'));
    await tester.pump();
    expect(find.text('登录后可关注'), findsOneWidget);
    expect(followIndex.isFollowed('42'), isFalse);
    await tester.pumpAndSettle();

    await tester.tap(find.text('加入黑名单'));
    await tester.pump();
    expect(find.text('登录后可管理黑名单'), findsOneWidget);
    expect(find.byType(UserBlockSheetIdentity), findsNothing);
    expect(userBlockIndex.isBlocked('42'), isFalse);
    await tester.pumpAndSettle();
  });

  testWidgets('本人资料页不展示关注和黑名单操作', (tester) async {
    final previous = chhSession.badges;
    chhSession.badges = const HeaderBadges(notices: 0, messages: 0, uid: '42');
    addTearDown(() => chhSession.badges = previous);
    await tester.pumpWidget(
      _app(UserPage(uid: '42', repository: FixtureSpace())),
    );
    await tester.pumpAndSettle();
    expect(find.text('关注'), findsNothing);
    expect(find.text('加入黑名单'), findsNothing);
  });

  testWidgets('从楼层打开的资料抽屉将来源写入黑名单', (tester) async {
    const source = BlockedUserSource(
      tid: 188,
      pid: 361,
      floor: 12,
      title: '本地帖子',
      excerpt: '这层的正文',
    );
    final blocks = UserBlockIndex.forTesting(null);
    addTearDown(blocks.dispose);
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showUserDrawer(
                context,
                '42',
                repository: FixtureSpace(),
                blockIndex: blocks,
                blockSource: source,
              ),
              child: const Text('打开楼主资料'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开楼主资料'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('加入黑名单'));
    await tester.pumpAndSettle();
    expect(find.text('来自《本地帖子》'), findsOneWidget);
    expect(find.text('#12'), findsOneWidget);
    await tester.tap(find.widgetWithText(UserBlockSheetButton, '加入黑名单'));
    await tester.pumpAndSettle();
    expect(blocks.entryFor('42')?.src?.pid, 361);
    expect(blocks.entryFor('42')?.src?.excerpt, '这层的正文');
    await tester.pump(const Duration(seconds: 5));
  });
}
