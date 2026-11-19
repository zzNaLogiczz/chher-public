import 'package:chh_app/core/display_time.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/widgets/post_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final entry in ['主楼', '原楼层', '评论视图']) {
    testWidgets('$entry点评复用友好时间，保留未知原文，缺少时间时不补造', (tester) async {
      final now = DateTime.now();
      final yesterday = DateTime(now.year, now.month, now.day - 1);
      final thisYear = DateTime(now.year, now.month == 11 ? 10 : 11, 3);
      final lastYear = DateTime(now.year - 1, 11, 3);
      String stamp(DateTime date) =>
          '${date.year}-${date.month}-${date.day} 19:48';
      final samples = <(String?, String?)>[
        (stamp(now), formatDisplayTime(raw: stamp(now), now: now)),
        (stamp(yesterday), '昨天 19:48'),
        (stamp(thisYear), '${thisYear.month}月3日 19:48'),
        (stamp(lastYear), '${lastYear.year}年11月3日'),
        ('时间未知', '时间未知'),
        (null, null),
        ('', null),
      ];
      final comments = [
        for (var i = 0; i < samples.length; i++)
          PostComment(author: '合成作者$i', text: '合成点评$i', timeRaw: samples[i].$1),
      ];
      for (final style in AppearanceStyle.values) {
        for (final brightness in Brightness.values) {
          await tester.pumpWidget(
            MaterialApp(
              theme: buildAppTheme(brightness, style),
              home: MediaQuery(
                data: const MediaQueryData(disableAnimations: true),
                child: Scaffold(
                  body: SingleChildScrollView(
                    key: ValueKey('$style-$brightness'),
                    child: switch (entry) {
                      '主楼' => OpeningFeedback(comments: comments),
                      '原楼层' => FloorFeedback(comments: comments),
                      _ => CommentFeedback(comments: comments),
                    },
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text(entry == '评论视图' ? '点评 7' : '展开全部 7 条点评'));
          await tester.pumpAndSettle();

          for (var i = 0; i < samples.length; i++) {
            final (raw, expected) = samples[i];
            expect(find.text('合成作者$i'), findsOneWidget);
            expect(find.text('合成点评$i'), findsOneWidget);
            if (expected != null) {
              final time = find.text(expected);
              expect(tester.widget<Text>(time).maxLines, 1);
              expect(
                tester.getCenter(time).dy,
                closeTo(tester.getCenter(find.text('合成作者$i')).dy, .01),
              );
              if (raw != expected) expect(find.text(raw!), findsNothing);
            }
          }
          expect(find.text(''), findsNothing);
          expect(tester.takeException(), isNull);
        }
      }
    });
  }
}
