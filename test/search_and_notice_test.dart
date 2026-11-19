import 'package:chh_app/models/models.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/ui/plain_rows.dart';
import 'package:chh_app/ui/search_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child) => MaterialApp(
  theme: buildAppTheme(Brightness.light),
  home: Scaffold(body: ListView(children: [child])),
);

void main() {
  testWidgets('unread notices show a leading dot, read ones do not', (
    tester,
  ) async {
    Widget row(bool unread) => app(
      NoticeRow(
        avatar: const SizedBox.square(dimension: 44),
        name: '测试回复者甲',
        time: '16:37',
        text: '回复了你的帖子',
        unread: unread,
        onTap: () {},
      ),
    );
    await tester.pumpWidget(row(true));
    expect(find.byKey(NoticeRow.unreadDotKey), findsOneWidget);
    await tester.pumpWidget(row(false));
    expect(find.byKey(NoticeRow.unreadDotKey), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byKey(NoticeRow.unreadDotKey), findsNothing);
    expect(find.text('16:37'), findsOneWidget);
  });

  testWidgets('capsule clear appears only with text and clears the query', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      app(
        SearchCapsule(
          controller: controller,
          hint: '查找版块',
          onClear: controller.clear,
        ),
      ),
    );
    final capsule = tester.getSize(find.byKey(SearchCapsule.surfaceKey));
    expect(capsule.height, 40);
    final clear = find.byTooltip('清除搜索');
    expect(
      tester
          .widget<IgnorePointer>(
            find
                .ancestor(of: clear, matching: find.byType(IgnorePointer))
                .first,
          )
          .ignoring,
      isTrue,
    );
    await tester.enterText(find.byType(EditableText), '装机');
    await tester.pumpAndSettle();
    await tester.tap(clear);
    await tester.pumpAndSettle();
    expect(controller.text, isEmpty);
  });

  testWidgets('result titles highlight the query in accent', (tester) async {
    await tester.pumpWidget(
      app(
        ThreadRow(
          thread: const ThreadSummary(
            tid: 40,
            title: '小机箱装机的散热与走线',
            snippet: '这次装机重点在进风路径',
            forumName: '电脑讨论(新)',
            author: '示例用户',
            createdAtRaw: '2020-1-1 12:00',
            replies: 6,
            views: 0,
          ),
          query: '装机',
          onTap: () {},
        ),
      ),
    );
    final title = tester.widget<RichText>(
      find
          .descendant(
            of: find.byType(ThreadRow),
            matching: find.byType(RichText),
          )
          .first,
    );
    final spans = <TextSpan>[];
    title.text.visitChildren((span) {
      if (span is TextSpan && span.text != null) spans.add(span);
      return true;
    });
    final hit = spans.firstWhere((s) => s.text == '装机');
    expect(hit.style?.color, AppTokens.light.accent);
    Text resultText(String text) => tester.widget<Text>(
      find.byWidgetPredicate(
        (w) => w is Text && w.textSpan?.toPlainText() == text,
      ),
    );
    expect(resultText('小机箱装机的散热与走线').maxLines, 1);
    expect(resultText('这次装机重点在进风路径').maxLines, 2);
    expect(find.text('电脑讨论'), findsOneWidget);
    expect(find.text('示例用户'), findsOneWidget);
    expect(find.text('2020年1月1日'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    expect(find.byKey(const ValueKey('thread-avatar-40')), findsNothing);
    expect(find.textContaining('·'), findsNothing);
  });
}
