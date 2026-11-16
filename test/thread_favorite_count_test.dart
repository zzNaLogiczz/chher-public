import 'package:chh_app/design/theme.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/thread_detail_page.dart';
import 'package:chh_app/parser/thread_parser.dart';
import 'package:chh_app/ui/favorite_action.dart';
import 'package:chh_app/ui/reading_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _action(String count, {int tid = 123, String host = ''}) =>
    '<a id="k_favorite" href="${host}home.php?mod=spacecp&amp;ac=favorite&amp;type=thread&amp;id=$tid">'
    '<i>收藏<span id="favoritenumber">$count</span></i></a>';

void main() {
  test('favorite totals use the matching thread action, including zero', () {
    for (final item in {'65': 65, '1,234': 1234, '0': 0, '': 0}.entries) {
      expect(
        parseThread(_action(item.key), tid: 123).favoriteCount,
        item.value,
      );
    }
    for (final markup in [
      '<p>收藏 99</p>',
      _action('99', tid: 456),
      _action('99', host: 'https://example.invalid/'),
      '<table><tr><td id="postmessage_1">${_action('99')}</td></tr></table>',
      '<div class="sign">${_action('99')}</div>',
      _action('1万'),
      _action('-1'),
      _action('1,2'),
      '<a id="k_favorite">收藏</a>',
    ]) {
      expect(parseThread(markup, tid: 123).favoriteCount, isNull);
    }
  });

  testWidgets(
    'favorite pill shows authoritative zero and count, hides unknown',
    (tester) async {
      for (final count in [null, 0, 65]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(Brightness.light),
            home: Scaffold(
              body: ReadingBar(
                placeholder: '写回复…',
                onCompose: () {},
                inComments: false,
                onShowComments: () {},
                onBackToTop: () {},
                favorited: false,
                favoriteCount: count,
              ),
            ),
          ),
        );
        expect(
          find.text('$count'),
          count == null ? findsNothing : findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'favorite count survives pagination and refresh keeps read content',
    (tester) async {
      var fresh = false;
      final reads = <(int, bool)>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: ThreadDetailPage(
            tid: 123,
            title: '收藏数',
            loadPage: (page, _, refresh) async {
              reads.add((page, refresh));
              return ThreadDetail(
                tid: 123,
                title: '收藏数',
                favoriteCount: page == 1 ? (fresh ? 5 : 4) : null,
                page: PageInfo(current: page, hasNext: page == 1),
                posts: [
                  Post(
                    pid: page,
                    floor: page,
                    author: '作者',
                    timeRaw: '',
                    content: [TextBlock(fresh ? '刷新的正文' : '原始正文$page')],
                  ),
                ],
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(reads, contains((2, false)));
      expect(
        tester.widget<ReadingBar>(find.byType(ReadingBar)).favoriteCount,
        4,
      );
      fresh = true;
      tester
          .widget<FavoriteActionBuilder>(find.byType(FavoriteActionBuilder))
          .onChanged!();
      await tester.pumpAndSettle();
      expect(reads, contains((1, true)));
      expect(
        tester.widget<ReadingBar>(find.byType(ReadingBar)).favoriteCount,
        5,
      );
      expect(find.text('刷新的正文'), findsNothing);
      expect(find.text('原始正文1'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
