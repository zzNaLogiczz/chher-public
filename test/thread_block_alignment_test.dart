import 'package:chh_app/design/theme.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/thread_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('楼主正文里的短段落靠左，不因外层 Column 默认居中而居中', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: ThreadDetailPage(
          tid: 1,
          title: '高阶刹车教学视频',
          loadPage: (page, _, _) async => ThreadDetail(
            tid: 1,
            fid: 290,
            title: '高阶刹车教学视频',
            posts: [
              Post(
                pid: 10,
                floor: 1,
                author: '楼主',
                authorUid: '10',
                timeRaw: '',
                content: const [
                  TextBlock('1.踩死，用力踩，如果没办法用力踩的话，座椅再往前。'),
                  TextBlock('2.随便踩'),
                ],
              ),
            ],
            page: const PageInfo(current: 1, hasNext: false),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final long = tester.getTopLeft(find.textContaining('1.踩死'));
    final short = tester.getTopLeft(find.text('2.随便踩'));
    // 正文左右内边距 24;不足一行的段落也从左边开始
    expect(long.dx, 24);
    expect(short.dx, 24);
  });
}
