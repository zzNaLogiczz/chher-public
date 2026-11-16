import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/di.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/forum_index_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solar_icons/solar_icons.dart';

void main() {
  setUp(() {
    chhSession.loggedIn = true;
    favoriteIndex.setUid(1);
    favoriteIndex.merge(const [
      FavoriteItem(
        type: FavoriteType.forum,
        targetId: 1,
        favid: '1',
        title: '旧名称',
        url: '',
      ),
      FavoriteItem(
        type: FavoriteType.forum,
        targetId: 99,
        favid: '99',
        title: '分享收藏',
        url: '',
      ),
    ]);
  });
  tearDown(() {
    chhSession.loggedIn = false;
    favoriteIndex.setUid(null);
  });

  for (final style in AppearanceStyle.values) {
    for (final brightness in Brightness.values) {
      testWidgets('$style $brightness directory markers and semantics', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(390, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final semantics = tester.ensureSemantics();
        var loads = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(brightness, style),
            home: ForumIndexView(
              loadForums: (_) async {
                loads++;
                return const [
                  ForumCategory(
                    name: '讨论区 - 硬件话题',
                    forums: [
                      Forum(
                        fid: 1,
                        name: '电脑讨论(新)',
                        threadCount: 123,
                        lastPostTimeRaw: '今天 17:42',
                      ),
                    ],
                  ),
                  ForumCategory(
                    name: '互动区',
                    forums: [Forum(fid: 2, name: '自由水世界2025')],
                  ),
                  ForumCategory(
                    name: '分享区',
                    forums: [Forum(fid: 3, name: '原创分享(新)')],
                  ),
                  ForumCategory(
                    name: '站务区',
                    forums: [Forum(fid: 4, name: '建议意见及投诉')],
                  ),
                  ForumCategory(
                    name: '数码区 - 讨论与分享',
                    forums: [Forum(fid: 5, name: '摄影')],
                  ),
                ];
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        final t = AppTokens.of(tester.element(find.byType(ForumIndexView)));
        final expected = {
          1: (tint: t.tintDai, icon: SolarIconsOutline.cpuBolt),
          2: (tint: t.tintTan, icon: SolarIconsOutline.cupHot),
          3: (tint: t.tintCi, icon: SolarIconsOutline.boxMinimalistic),
          4: (tint: t.tintMo, icon: SolarIconsOutline.mailbox),
          5: (tint: t.tintZhe, icon: SolarIconsOutline.layersMinimalistic),
          99: (tint: t.tintZhe, icon: SolarIconsOutline.boxMinimalistic),
        };
        final markerColors = <Color>[];
        for (final entry in expected.entries) {
          final rows = find.byKey(ValueKey('forum-row-${entry.key}'));
          expect(rows, findsNWidgets(entry.key == 1 ? 2 : 1));
          for (var i = 0; i < rows.evaluate().length; i++) {
            final row = rows.at(i);
            final iconFinder = find.descendant(
              of: row,
              matching: find.byIcon(entry.value.icon),
            );
            expect(iconFinder, findsOneWidget);
            final icon = tester.widget<Icon>(iconFinder);
            expect(icon.size, 20);
            expect(
              icon.color,
              t.isDark
                  ? Color.lerp(entry.value.tint, t.text, .5)
                  : entry.value.tint,
            );
            final markerFinder = find.ancestor(
              of: iconFinder,
              matching: find.byWidgetPredicate(
                (w) => w is Container && w.constraints?.maxWidth == 36,
              ),
            );
            final marker = tester.widget<Container>(markerFinder);
            final decoration = marker.decoration! as BoxDecoration;
            expect(tester.getSize(markerFinder), const Size(36, 36));
            expect(marker.alignment, Alignment.center);
            expect(decoration.borderRadius, BorderRadius.circular(12));
            expect(
              decoration.color,
              Color.alphaBlend(
                entry.value.tint.withValues(alpha: t.isDark ? .30 : .13),
                t.surface,
              ),
            );
            expect(decoration.color!.a, 1);
            if (entry.key == 1) markerColors.add(decoration.color!);
            expect(
              find.ancestor(
                of: iconFinder,
                matching: find.byWidgetPredicate(
                  (w) => w is ExcludeSemantics && w.excluding,
                ),
              ),
              findsWidgets,
            );
            final data = tester.getSemantics(row).getSemanticsData();
            expect(data.hasAction(SemanticsAction.tap), isTrue);
            expect(
              data.label,
              isNot(contains(String.fromCharCode(icon.icon!.codePoint))),
            );
          }
        }
        expect(markerColors[0], markerColors[1]);
        expect(find.text('旧名称'), findsNothing);
        for (final initial in ['电', '自', '原', '建', '摄', '分']) {
          expect(find.text(initial), findsNothing);
        }
        for (var i = 0; i < 2; i++) {
          final row = find.byKey(const ValueKey('forum-row-1')).at(i);
          expect(tester.getSemantics(row).label, '电脑讨论(新)\n今天 17:42\n123 个主题');
        }
        semantics.dispose();
        expect(loads, 1);
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
