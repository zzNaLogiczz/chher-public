import 'dart:io';

import 'package:chh_app/design/theme.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/ui/cards.dart';
import 'package:chh_app/ui/plain_rows.dart';
import 'package:chh_app/ui/section_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child) => MaterialApp(
  theme: buildAppTheme(Brightness.light),
  home: Scaffold(body: ListView(children: [child])),
);

void main() {
  test('feed title row carries search and the bell is gone', () {
    final source = File('lib/pages/feed_page.dart').readAsStringSync();
    expect(source, contains('LargeTitleHeader('));
    expect(source, contains("tag: 'search-entry-feed'"));
    expect(source, isNot(contains('MessagesAction')));
    expect(source, isNot(contains('SliverAppBar(')));
  });

  testWidgets('review rows show a thumbnail only when one is given', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        Column(
          children: [
            ArticleRow(
              title: '有封面的评测',
              eyebrow: '主板',
              thumbnail: const ColoredBox(
                key: ValueKey('thumb'),
                color: Colors.grey,
              ),
              onTap: () {},
            ),
            ArticleRow(title: '没有封面的评测', onTap: () {}),
          ],
        ),
      ),
    );
    expect(find.byKey(const ValueKey('thumb')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('thumb'))),
      const Size(88, 60),
    );
    expect(tester.getTopLeft(find.text('没有封面的评测')).dx, 20);
    expect(tester.getTopLeft(find.text('有封面的评测')).dx, greaterThan(20 + 88));
    final source = File('lib/pages/feed_page.dart').readAsStringSync();
    expect(source, contains('(a.coverUrl?.isNotEmpty ?? false)'));
  });

  testWidgets('shelf cards put titles below images', (tester) async {
    await tester.pumpWidget(
      app(
        Align(
          alignment: Alignment.topLeft,
          child: ShelfCard(
            image: const ColoredBox(key: ValueKey('image'), color: Colors.grey),
            title: '男女生视角体验阿联酋航空头等舱',
            source: '灵感与日常',
            onTap: () {},
          ),
        ),
      ),
    );
    final image = tester.getRect(find.byKey(const ValueKey('image')));
    expect(image.width, ShelfCard.width);
    expect(image.height, closeTo(ShelfCard.width * 9 / 16, .5));
    expect(
      tester.getTopLeft(find.text('男女生视角体验阿联酋航空头等舱')).dy,
      greaterThanOrEqualTo(image.bottom),
    );
  });

  testWidgets('shelf cards keep one height for short and long titles', (
    tester,
  ) async {
    for (final scale in [1.0, 2.0]) {
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: app(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShelfCard(
                  key: const ValueKey('short'),
                  image: const ColoredBox(color: Colors.grey),
                  title: '短标题',
                  source: '灵感与日常',
                  onTap: () {},
                ),
                ShelfCard(
                  key: const ValueKey('long'),
                  image: const ColoredBox(color: Colors.grey),
                  title: '男女生视角体验阿联酋航空头等舱，从值机到落地的完整记录与细节',
                  source: '灵感与日常',
                  onTap: () {},
                ),
              ],
            ),
          ),
        ),
      );
      final short = tester.getSize(find.byKey(const ValueKey('short')));
      final long = tester.getSize(find.byKey(const ValueKey('long')));
      expect(short.height, long.height);
      expect(
        short.height,
        closeTo(ShelfCard.heightFor(TextScaler.linear(scale)), .5),
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('feed sections share one 20dp leading edge', (tester) async {
    await tester.pumpWidget(
      app(
        Column(
          children: [
            SectionHeader(title: '更多评测', actionLabel: '全部', onAction: () {}),
            ArticleRow(title: '评测标题', onTap: () {}),
            const SectionHeader(title: '快讯'),
            NewsRow(title: '快讯标题', onTap: () {}),
            const SectionHeader(title: '社区讨论'),
            ThreadRow(
              thread: const ThreadSummary(
                tid: 1,
                title: '讨论标题',
                author: '甲',
                replies: 0,
                views: 0,
              ),
              onTap: () {},
            ),
          ],
        ),
      ),
    );
    for (final text in ['更多评测', '评测标题', '快讯', '快讯标题', '社区讨论', '讨论标题']) {
      expect(tester.getTopLeft(find.text(text)).dx, 20, reason: text);
    }
  });
}
