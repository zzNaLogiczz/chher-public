import 'package:chh_app/design/theme.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/ui/hit_slop.dart';
import 'package:chh_app/widgets/post_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('solid more aligns and fits dark=$dark scale=$scale', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var more = 0, reply = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(dark ? Brightness.dark : Brightness.light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: Scaffold(
              body: HitSlopRegion(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      PostCard.header(
                        post: Post(
                          pid: 7,
                          floor: 1,
                          author: '超长昵称测试用户Alpha非常长的名字',
                          timeRaw: '2026-11-04',
                          content: const [],
                        ),
                        isOpening: true,
                        onMore: () => more++,
                      ),
                      CommentMetaRow(
                        timeLabel: '昨天',
                        onReply: () => reply++,
                        onMore: () => more++,
                        moreKey: const ValueKey('more'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('…'), findsNothing);
        final icons = find.byType(SolidMoreIcon);
        expect(icons, findsNWidgets(2));
        final opening = tester.getRect(
          find.byKey(const ValueKey('post-more-7')),
        );
        final author = tester.getRect(
          find.byKey(const ValueKey('post-profile-7')),
        );
        expect(opening.size, const Size(44, 44));
        expect(opening.center.dy, closeTo(author.center.dy, .01));
        expect(tester.getSize(icons.first), const Size(18, 18));
        expect(tester.getSize(icons.last), const Size(16, 16));
        final compact = tester.getRect(find.byKey(const ValueKey('more')));
        expect(
          compact.height,
          closeTo((13 * scale * 1.4).clamp(20, double.infinity), .01),
        ); // Transparent slop must not raise the row.
        final replyRect = tester.getRect(find.text('回复'));
        expect(compact.center.dy, closeTo(replyRect.center.dy, 2));
        for (final point in [
          Offset(compact.left + 1, compact.center.dy),
          Offset(compact.right - 1, compact.center.dy),
          Offset(compact.center.dx, compact.center.dy - 21),
          Offset(compact.center.dx, compact.center.dy + 21),
        ]) {
          await tester.tapAt(point);
          await tester.pumpAndSettle();
        }
        expect(more, 4);
        await tester.tap(find.text('回复'));
        await tester.pumpAndSettle();
        expect(reply, 1);
        expect(more, 4);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
