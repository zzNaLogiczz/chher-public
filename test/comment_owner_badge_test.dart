import 'package:chh_app/pages/thread_detail_page.dart';
import 'package:flutter_test/flutter_test.dart';

import 'thread_inline_replies_test.dart' show expand;
import 'threaded_thread_page_test.dart' as fixture;

Finder badgeIn(int pid) =>
    find.descendant(of: fixture.card(pid), matching: find.text('楼主'));

void main() {
  testWidgets('评论区里楼主的评论和楼中楼回复都标出楼主', (tester) async {
    await fixture.pump(
      tester,
      ThreadDetailPage(
        tid: 123,
        title: '楼主回复',
        loadPage: (_, _, _) async => fixture.page([
          fixture.post(1),
          fixture.post(2),
          // 楼主在 2 楼下面回复
          fixture.post(3, target: 2, uid: '1'),
          // 楼主直接发的评论
          fixture.post(4, uid: '1'),
        ]),
      ),
    );
    await fixture.bottom(tester);
    expect(badgeIn(4), findsOneWidget);
    expect(badgeIn(2), findsNothing);

    await expand(tester);
    expect(badgeIn(3), findsOneWidget);
    expect(badgeIn(2), findsNothing);
  });
}
