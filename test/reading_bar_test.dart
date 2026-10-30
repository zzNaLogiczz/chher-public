import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/icons.dart';
import 'package:chh_app/ui/press.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/ui/quote.dart';
import 'package:chh_app/ui/reading_bar.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/widgets/post_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child, {double textScale = 1}) => MaterialApp(
  theme: buildAppTheme(Brightness.light),
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: Align(alignment: Alignment.bottomCenter, child: child),
      ),
    ),
  ),
);

void main() {
  postCardTests();
  testWidgets(
    'favorite circle precedes compose and leaves right action fixed',
    (tester) async {
      Widget bar({bool? favorited, bool busy = false, VoidCallback? toggle}) =>
          app(
            ReadingBar(
              placeholder: '写回复…',
              onCompose: () {},
              count: 9,
              inComments: false,
              onShowComments: () {},
              onBackToTop: () {},
              favorited: favorited,
              favoriteBusy: busy,
              onToggleFavorite: toggle,
            ),
          );
      await tester.pumpWidget(bar());
      final originalRight = tester.getRect(find.byKey(ReadingBar.actionKey));
      expect(find.byKey(ReadingBar.favoriteKey), findsNothing);
      var tapped = 0;
      await tester.pumpWidget(bar(favorited: false, toggle: () => tapped++));
      await tester.pumpAndSettle();
      final favorite = tester.getRect(find.byKey(ReadingBar.favoriteKey));
      final compose = tester.getRect(find.byType(ComposeCapsule));
      expect(favorite.size, const Size(44, 44));
      expect(favorite.right, lessThan(compose.left));
      expect(compose.right, lessThan(originalRight.left));
      expect(tester.getRect(find.byKey(ReadingBar.actionKey)), originalRight);
      expect(find.byTooltip('收藏'), findsOneWidget);
      await tester.tap(find.byKey(ReadingBar.favoriteKey));
      expect(tapped, 1);
      await tester.pumpWidget(
        bar(favorited: true, busy: true, toggle: () => tapped++),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('取消收藏'), findsOneWidget);
      expect(
        tester.widget<PressScale>(find.byKey(ReadingBar.favoriteKey)).onTap,
        isNull,
      );
      final filled = find.byIcon(AppIcons.bookmarkFilled);
      expect(filled, findsOneWidget);
      expect(tester.widget<Icon>(filled).color, AppTokens.light.accent);
      await tester.tap(find.byKey(ReadingBar.favoriteKey));
      expect(tapped, 1);
    },
  );

  testWidgets('favorite icons change immediately with reduced motion', (
    tester,
  ) async {
    var favorited = false;
    late StateSetter rebuild;
    await tester.pumpWidget(
      app(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return ReadingBar(
                placeholder: '写回复…',
                onCompose: () {},
                inComments: false,
                onShowComments: () {},
                onBackToTop: () {},
                favorited: favorited,
              );
            },
          ),
        ),
      ),
    );
    double opacity(IconData icon) => tester
        .widget<Opacity>(
          find
              .ancestor(of: find.byIcon(icon), matching: find.byType(Opacity))
              .first,
        )
        .opacity;
    expect(opacity(AppIcons.bookmark), 1);
    expect(opacity(AppIcons.bookmarkFilled), 0);
    rebuild(() => favorited = true);
    await tester.pump();
    expect(opacity(AppIcons.bookmark), 0);
    expect(opacity(AppIcons.bookmarkFilled), 1);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets(
    'circle shows the count in the body and back-to-top in comments',
    (tester) async {
      var shown = 0, top = 0, composed = 0;
      Widget bar(bool inComments) => app(
        ReadingBar(
          placeholder: '写回复…',
          onCompose: () => composed++,
          count: 65,
          inComments: inComments,
          onShowComments: () => shown++,
          onBackToTop: () => top++,
        ),
      );
      await tester.pumpWidget(bar(false));
      await tester.pumpAndSettle();
      expect(find.text('65'), findsOneWidget);
      await tester.tap(find.byKey(ReadingBar.actionKey));
      expect(shown, 1);
      await tester.tap(find.text('写回复…'));
      expect(composed, 1);

      await tester.pumpWidget(bar(true));
      await tester.pumpAndSettle();
      expect(find.text('65'), findsNothing);
      expect(find.byTooltip('回到顶部'), findsOneWidget);
      await tester.tap(find.byKey(ReadingBar.actionKey));
      expect(top, 1);
    },
  );

  testWidgets('reading bar fits 320dp at 2x text', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      app(
        ReadingBar(
          placeholder: '写评论…',
          onCompose: () {},
          favorited: false,
          onToggleFavorite: () {},
          count: 1234,
          inComments: false,
          onShowComments: () {},
          onBackToTop: () {},
        ),
        textScale: 2,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.widget<Text>(find.text('写评论…')).maxLines, 1);
  });

  testWidgets('quote block draws a leading rule, not a filled box', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(const QuoteView(author: '测试回复者甲', text: '能挂个蓝奏不，不想下网盘APP端')),
    );
    final boxes = tester.widgetList<DecoratedBox>(
      find.descendant(
        of: find.byType(QuoteView),
        matching: find.byType(DecoratedBox),
      ),
    );
    final filled = boxes.where((b) {
      final d = b.decoration;
      return d is BoxDecoration && d.color != null && d.color!.a > 0;
    });
    expect(filled, isEmpty);
    final rule = boxes.firstWhere((b) {
      final d = b.decoration;
      return d is BoxDecoration && d.border is Border;
    });
    final left = ((rule.decoration as BoxDecoration).border! as Border).left;
    expect(left.width, 3);
    expect(left.color, AppTokens.light.fill2);
    expect(find.text('测试回复者甲'), findsOneWidget);
  });

  testWidgets('long quotes collapse to two lines and expand on tap', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const QuoteView(
          author: '测试回复者甲',
          text:
              '很长很长的引用内容很长很长的引用内容很长很长的引用内容很长很长的引用内容很长很长的引用内容很长很长的引用内容很长很长的引用内容'
              '很长很长的引用内容很长很长的引用内容很长很长的引用内容很长很长的引用内容很长很长的引用内容很长很长的引用内容很长很长的引用内容'
              '很长很长的引用内容很长很长的引用内容很长很长的引用内容很长很长的引用内容很长很长的引用内容很长很长的引用内容很长很长的引用内容',
        ),
      ),
    );
    Text body() => tester.widget<Text>(find.textContaining('很长很长'));
    expect(body().maxLines, 2);
    expect(find.text('展开引用'), findsOneWidget);
    await tester.tap(find.byType(QuoteView));
    await tester.pumpAndSettle();
    expect(body().maxLines, isNull);
    expect(find.text('收起引用'), findsOneWidget);
  });
}

Widget postApp(Widget child) => MaterialApp(
  theme: buildAppTheme(Brightness.light),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void postCardTests() {
  testWidgets('comment reply is a light text action, not accent', (
    tester,
  ) async {
    const comment = Post(
      pid: 7,
      floor: 7,
      author: '测试回复者乙',
      timeRaw: '2026-10-23 15:48',
      content: [TextBlock('要**打不开')],
    );
    await tester.pumpWidget(
      postApp(
        PostCard(
          post: comment,
          isOpening: false,
          commentStyle: true,
          onReply: () {},
        ),
      ),
    );
    final label = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('comment-reply-7')),
        matching: find.text('回复'),
      ),
    );
    expect(label.style!.color, AppTokens.light.text2);
  });

  testWidgets('opening post hides #1 and replies use a text reply action', (
    tester,
  ) async {
    const opening = Post(
      pid: 1,
      floor: 1,
      author: '测试发布者',
      timeRaw: '2026-10-25 22:22',
      content: [TextBlock('首楼正文')],
    );
    await tester.pumpWidget(
      postApp(PostCard(post: opening, isOpening: true, onReply: () {})),
    );
    expect(find.text('#1'), findsNothing);
    expect(find.text('楼主'), findsOneWidget);

    const reply = Post(
      pid: 3,
      floor: 3,
      author: 'Gone',
      timeRaw: '2026-10-23 16:05',
      content: [TextBlock('哈哈，就是牛逼，谢谢！')],
    );
    await tester.pumpWidget(
      postApp(PostCard(post: reply, isOpening: false, onReply: () {})),
    );
    expect(find.text('#3'), findsOneWidget);
    final action = tester.widget<Text>(find.text('回复 #3'));
    expect(action.style!.color, AppTokens.light.text3);
    // 回复不再是灰色胶囊:动作周围没有填充底色的 DecoratedBox
    final filled = tester
        .widgetList<DecoratedBox>(
          find.ancestor(
            of: find.text('回复 #3'),
            matching: find.byType(DecoratedBox),
          ),
        )
        .where((b) {
          final d = b.decoration;
          return d is BoxDecoration && d.color == AppTokens.light.fill;
        });
    expect(filled, isEmpty);
  });
}
