import 'package:chh_app/core/reading_prefs.dart';
import 'package:chh_app/design/reading.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/models/article_discussion.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/article_discussion_page.dart';
import 'package:chh_app/ui/hit_slop.dart';
import 'package:chh_app/ui/picker.dart';
import 'package:chh_app/widgets/article_discussion_widgets.dart';
import 'package:chh_app/widgets/article_reply_sheet.dart';
import 'package:chh_app/widgets/comment_mode_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const body = '合成评论正文第一行\n合成评论正文第二行';
const quoted = '合成引用第一行\n合成引用第二行';
const discussion = ArticleDiscussion(
  aid: 1,
  title: '合成阅读测试',
  authorUid: 'author',
  page: PageInfo(current: 1, hasNext: false),
  items: [
    ArticleComment(
      cid: 1,
      author: '合成作者',
      authorUid: 'author',
      timeRaw: '2001-01-02 09:30',
      text: body,
      content: [
        TextBlock(body),
        QuoteBlock([TextBlock(quoted)]),
      ],
    ),
    ArticleComment(
      cid: 2,
      author: '合成回复者',
      timeRaw: '2001-01-03 09:30',
      text: '合成楼中楼',
      content: [
        QuoteBlock([TextBlock('合成作者: $body')]),
        TextBlock('合成楼中楼'),
      ],
    ),
    ArticleComment(cid: 3, author: '其他读者', text: '独立合成评论'),
  ],
);

Finder tile(int cid) => find.byKey(ValueKey('comment-$cid'));
Finder inside(Finder parent, Type type) =>
    find.descendant(of: parent, matching: find.byType(type));
Finder textIn(Finder parent, String text) =>
    find.descendant(of: parent, matching: find.text(text));

Future<void> mount(
  WidgetTester tester,
  ReadingPrefsController controller, {
  bool sheet = true,
  double width = 390,
  double scale = 1,
  VoidCallback? onLogin,
}) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ReadingScope(
      controller: controller,
      child: MaterialApp(
        theme: buildAppTheme(
          Brightness.light,
        ).copyWith(platform: TargetPlatform.android),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: sheet
            ? Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => ArticleDiscussionPage.show(
                      context,
                      aid: 1,
                      title: discussion.title,
                      loadPage: (_, _) async => discussion,
                      isLoggedIn: () => false,
                      onLogin: (_) async => onLogin?.call(),
                    ),
                    child: const Text('打开合成评论'),
                  ),
                ),
              )
            : ArticleDiscussionPage(
                aid: 1,
                title: discussion.title,
                loadPage: (_, _) async => discussion,
                isLoggedIn: () => false,
              ),
      ),
    ),
  );
  if (sheet) await tester.tap(find.text('打开合成评论'));
  await tester.pumpAndSettle();
}

Future<void> pick(WidgetTester tester, String mode) async {
  final bar = find.byType(CommentModeBar);
  final value = tester.widget<CommentModeBar>(bar).mode;
  if (['评论', '原楼层', '只看作者'][value.index] == mode) return;
  final picker = inside(bar, PickerButton<CommentViewMode>);
  if (picker.evaluate().isNotEmpty) {
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(find.text(mode).last);
  } else {
    await tester.tap(textIn(bar, mode));
  }
  await tester.pumpAndSettle();
}

double baseline(WidgetTester tester, Finder text) {
  final paragraph = tester.renderObject<RenderParagraph>(
    inside(text, RichText),
  );
  final painter = TextPainter(
    text: paragraph.text,
    textDirection: paragraph.textDirection,
    textScaler: paragraph.textScaler,
    locale: paragraph.locale,
    strutStyle: paragraph.strutStyle,
    textHeightBehavior: paragraph.textHeightBehavior,
  )..layout(maxWidth: paragraph.size.width);
  final baseline = painter.computeLineMetrics().last.baseline;
  painter.dispose();
  return paragraph.localToGlobal(Offset(0, baseline)).dy;
}

void main() {
  for (final sheet in [true, false]) {
    for (final mode in ['评论', '原楼层', '只看作者']) {
      testWidgets('${sheet ? 'show弹层' : '独立页面'} $mode 同一controller更新布局', (
        tester,
      ) async {
        final controller = ReadingPrefsController(directory: () async => null);
        addTearDown(controller.dispose);
        await mount(tester, controller, sheet: sheet);
        await pick(tester, mode);
        final root = tile(1);
        final avatar = inside(root, ClipOval);
        final before = tester.getRect(root);
        final beforeAvatar = tester.getSize(avatar);
        final bodyBefore = tester.getSize(textIn(root, body));
        expect(before.left, 20);
        expect(beforeAvatar.width, 32);
        await controller.set(
          controller.prefs.copyWith(layout: ReadingLayout.compact),
        );
        await tester.pumpAndSettle();
        expect(tester.getRect(root).left, 16);
        expect(tester.getSize(avatar).width, 28);
        expect(tester.getSize(root).height, lessThan(before.height));
        expect(tester.getSize(textIn(root, body)).height, bodyBefore.height);
        if (mode != '只看作者') {
          final divider = tester
              .widgetList<Divider>(find.byType(Divider))
              .firstWhere((d) => d.thickness == .5);
          expect(divider.indent, 38);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('真实弹层字号与行距分别改变正文和折叠引用尺寸', (tester) async {
    final controller = ReadingPrefsController(directory: () async => null);
    addTearDown(controller.dispose);
    await mount(tester, controller);
    final content = textIn(tile(1), body);
    final quote = textIn(tile(1), quoted);
    final originalBody = tester.getSize(content).height;
    final originalQuote = tester.getSize(quote).height;
    await controller.set(
      controller.prefs.copyWith(fontSize: ReadingFontSize.xl),
    );
    await tester.pumpAndSettle();
    final largeBody = tester.getSize(content).height;
    final largeQuote = tester.getSize(quote).height;
    expect(largeBody, greaterThan(originalBody));
    expect(largeQuote, greaterThan(originalQuote));
    expect(tester.getSize(inside(tile(1), ClipOval)).width, 32);
    await controller.set(
      controller.prefs.copyWith(lineHeight: ReadingLineHeight.loose),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(content).height, greaterThan(largeBody));
    expect(tester.getSize(quote).height, greaterThan(largeQuote));
    await tester.tap(textIn(tile(1), '展开引用'));
    await tester.pumpAndSettle();
    final expanded = tester.getSize(find.byType(DiscussionQuote)).height;
    await controller.set(
      controller.prefs.copyWith(lineHeight: ReadingLineHeight.compact),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(DiscussionQuote)).height,
      lessThan(expanded),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('楼中楼头像缩进随布局更新且没有左竖线', (tester) async {
    final controller = ReadingPrefsController(directory: () async => null);
    addTearDown(controller.dispose);
    await mount(tester, controller);
    await tester.tap(find.byKey(const ValueKey('article-expand-replies-1')));
    await tester.pumpAndSettle();
    expect(tester.getRect(tile(2)).left - tester.getRect(tile(1)).left, 42);
    expect(tester.getSize(inside(tile(2), ClipOval)).width, 24);
    expect(inside(tile(2), DiscussionQuote), findsNothing);
    final borders = tester
        .widgetList<DecoratedBox>(inside(tile(2), DecoratedBox))
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .map((box) => box.border)
        .whereType<Border>();
    expect(
      borders.where((border) => border.left.style != BorderStyle.none),
      isEmpty,
    );
    await controller.set(
      controller.prefs.copyWith(layout: ReadingLayout.compact),
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(tile(2)).left - tester.getRect(tile(1)).left, 38);
    expect(tester.getSize(inside(tile(2), ClipOval)).width, 22);
    expect(tester.takeException(), isNull);
  });

  testWidgets('真实弹层轻量回复仍进入鉴权且时间不会误触', (tester) async {
    final controller = ReadingPrefsController(directory: () async => null);
    addTearDown(controller.dispose);
    var logins = 0;
    await mount(tester, controller, onLogin: () => logins++);
    await tester.tap(textIn(tile(1), '2001-01-02 09:30'));
    await tester.pumpAndSettle();
    expect(logins, 0);
    await tester.tap(find.byKey(const ValueKey('article-comment-reply-1')));
    await tester.pumpAndSettle();
    expect(logins, 1);
    expect(find.byType(ArticleReplySheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('时间保持原有格式与完整语义，无时间也能回复', (tester) async {
    var replies = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: Column(
            children: [
              ArticleCommentTile(
                comment: ArticleComment(
                  cid: 4,
                  author: '合成作者',
                  text: '合成正文',
                  time: DateTime(2001, 1, 2, 9, 30),
                  timeRaw: '2001-01-02 09:30',
                ),
                onReply: () => replies++,
              ),
              ArticleCommentTile(
                comment: const ArticleComment(
                  cid: 5,
                  author: '无时间作者',
                  text: '无时间正文',
                ),
                onReply: () => replies++,
              ),
            ],
          ),
        ),
      ),
    );
    expect(
      tester.widget<Text>(find.text('2001-01-02')).semanticsLabel,
      '2001-01-02 09:30',
    );
    await tester.tap(find.byKey(const ValueKey('article-comment-reply-5')));
    await tester.pumpAndSettle();
    expect(replies, 1);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('轻量时间回复行 对齐/透明命中/滚动 scale=$scale', (tester) async {
      var replies = 0;
      tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(
            Brightness.light,
          ).copyWith(platform: TargetPlatform.android),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: ArticleCommentTile(
                        comment: discussion.items.first,
                        onReply: () => replies++,
                      ),
                    ),
                    const SizedBox(height: 1800),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final root = find.byType(ArticleCommentTile);
      final reply = find.byKey(const ValueKey('article-comment-reply-1'));
      final time = textIn(root, '2001-01-02 09:30');
      final replyText = textIn(root, '回复');
      expect(tester.getSize(reply).height, lessThan(44));
      expect(
        tester.getTopLeft(time).dx,
        tester.getTopLeft(textIn(root, body)).dx,
      );
      expect(tester.widget<Text>(time).style!.color, AppTokens.light.text3);
      expect(tester.widget<Text>(replyText).style!.fontWeight, FontWeight.w600);
      final target = tester.widget<HitSlopTarget>(
        find.ancestor(of: reply, matching: find.byType(HitSlopTarget)),
      );
      final bounds = tester.getRect(reply);
      expect(bounds.width + target.slop.horizontal, greaterThanOrEqualTo(44));
      expect(bounds.height + target.slop.vertical, greaterThanOrEqualTo(44));
      if (scale == 1) {
        expect(
          baseline(tester, time) - baseline(tester, replyText),
          closeTo(13 * .08, .01),
        );
      } else {
        expect(bounds.top, greaterThan(tester.getRect(time).bottom));
      }
      await tester.tap(time);
      expect(replies, 0);
      await tester.tapAt(Offset(bounds.center.dx, bounds.bottom + 8));
      await tester.pumpAndSettle();
      expect(replies, 1);
      await tester.dragFrom(
        Offset(bounds.center.dx, bounds.bottom + 8),
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();
      expect(replies, 1);
      final scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      expect(scroll.position.pixels, greaterThan(0));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('窄屏2x真实弹层引用与多行内容无溢出且缩放受阅读上限约束', (tester) async {
    final controller = ReadingPrefsController(directory: () async => null);
    addTearDown(controller.dispose);
    await mount(tester, controller, width: 320, scale: 2);
    for (final mode in ['评论', '原楼层', '只看作者']) {
      await pick(tester, mode);
      await controller.set(
        controller.prefs.copyWith(
          fontSize: ReadingFontSize.xl,
          lineHeight: ReadingLineHeight.loose,
        ),
      );
      await tester.pumpAndSettle();
      final text = textIn(tile(1), quoted);
      final paragraph = tester.renderObject<RenderParagraph>(
        inside(text, RichText),
      );
      expect(paragraph.textScaler.scale(20), lessThanOrEqualTo(26));
      expect(tester.takeException(), isNull);
    }
  });
}
