import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/di.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/forum_index_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motor/motor.dart';
import 'package:solar_icons/solar_icons.dart';

void main() {
  setUp(() {
    chhSession.loggedIn = false;
    favoriteIndex.setUid(null);
  });
  tearDown(() {
    chhSession.loggedIn = false;
    favoriteIndex.setUid(null);
  });

  for (final style in AppearanceStyle.values) {
    for (final brightness in Brightness.values) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          '$style $brightness ${scale}x directory uses real counts and activity only',
          (tester) async {
            tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            await tester.pumpWidget(
              MaterialApp(
                theme: buildAppTheme(brightness, style),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: ForumIndexView(
                  loadForums: (_) async => const [
                    ForumCategory(
                      name: '硬件',
                      forums: [
                        Forum(
                          fid: 1,
                          name: '电脑讨论',
                          threadCount: 60000,
                          lastPostTimeRaw: '今天 17:42',
                        ),
                        Forum(fid: 2, name: '摄影讨论', postCount: 95000),
                      ],
                    ),
                  ],
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(find.text('6万 主题', findRichText: true), findsOneWidget);
            final name = tester.getRect(find.text('电脑讨论'));
            final activity = tester.getRect(find.text('今天 17:42'));
            final count = tester.getRect(
              find.byKey(const ValueKey('forum-count-1')),
            );
            expect(activity.top, greaterThanOrEqualTo(name.bottom));
            expect(activity.left, greaterThanOrEqualTo(name.left));
            expect(count.left, greaterThan(name.right));
            final row = tester.getRect(find.byKey(const ValueKey('forum-row-1')));
            expect(count.right, closeTo(row.right - 14, .1));
            expect(count.center.dy, lessThan(activity.center.dy));
            expect(find.text('今天 17:42'), findsOneWidget);
            expect(
              find.byKey(const ValueKey('forum-activity-1')),
              findsNothing,
            );
            expect(find.byKey(const ValueKey('forum-count-2')), findsNothing);
            expect(
              find.byKey(const ValueKey('forum-activity-2')),
              findsNothing,
            );
            expect(find.text('电'), findsNothing);
            expect(find.byIcon(SolarIconsOutline.cpuBolt), findsOneWidget);
            expect(find.text('2 个版块'), findsOneWidget);
            expect(tester.binding.transientCallbackCount, 0);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets(
    'jump sheet scrolls to distant category without filtering or eager rows',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var loads = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: ForumIndexView(
            loadForums: (_) async {
              loads++;
              return [
                ForumCategory(
                  name: '硬件',
                  forums: [
                    for (var i = 0; i < 1000; i++)
                      Forum(fid: i, name: '硬件版块 $i'),
                  ],
                ),
                const ForumCategory(
                  name: '生活',
                  forums: [Forum(fid: 1001, name: '摄影')],
                ),
              ];
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scroll = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!;
      scroll.jumpTo(140);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('forum-directory-jump')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('picker-option-1')));
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(10000));
      final targetOffset = scroll.offset;
      expect(find.text('摄影').hitTestable(), findsOneWidget);
      expect(find.textContaining('硬件版块').evaluate().length, lessThan(30));
      expect(loads, 1);
      await tester.tap(find.byKey(const ValueKey('forum-directory-jump')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('picker-option-0')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('picker-option-0')));
      await tester.pumpAndSettle();
      expect(find.text('硬件版块 0').hitTestable(), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('forum-directory-jump')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('picker-option-1')));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.drag(
        find.byType(CustomScrollView).first,
        const Offset(0, 300),
      );
      await tester.pumpAndSettle();
      expect(
        scroll.offset,
        lessThan(targetOffset - 100),
        reason:
            'A user drag cancels the follow-up correction as well as the spring',
      );
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('new favorite alone expands and reuses source metadata', (
    tester,
  ) async {
    chhSession.loggedIn = true;
    favoriteIndex.setUid(1);
    favoriteIndex.merge([
      const FavoriteItem(
        type: FavoriteType.forum,
        targetId: 1,
        favid: '1',
        title: '已收藏',
        url: '',
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: ForumIndexView(
          loadForums: (_) async => const [
            ForumCategory(
              name: '硬件',
              forums: [
                Forum(fid: 1, name: '已收藏', threadCount: 12),
                Forum(fid: 2, name: '新收藏', threadCount: 34),
              ],
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final firstRow = find.byKey(const ValueKey('forum-row-1')).first;
    final originalHeight = tester.getSize(firstRow).height;
    favoriteIndex.merge([
      const FavoriteItem(
        type: FavoriteType.forum,
        targetId: 2,
        favid: '2',
        title: '新收藏',
        url: '',
      ),
    ]);
    await tester.pump();
    final inserted = tester.widget<SingleMotionBuilder>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('forum-row-2')).first,
            matching: find.byType(SingleMotionBuilder),
          )
          .first,
    );
    expect(inserted.from, 0);
    expect(tester.getSize(firstRow).height, originalHeight);
    await tester.pumpAndSettle();
    expect(find.text('34 主题'), findsNWidgets(2));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
