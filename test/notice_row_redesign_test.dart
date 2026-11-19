import 'package:chh_app/design/icons.dart';
import 'package:chh_app/design/notice_tokens.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/ui/plain_rows.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(
  Widget child, {
  Brightness brightness = Brightness.light,
  AppearanceStyle style = AppearanceStyle.cinnabar,
  bool reduced = false,
  double scale = 1,
}) => MaterialApp(
  theme: buildAppTheme(brightness, style),
  home: MediaQuery(
    data: MediaQueryData(
      disableAnimations: reduced,
      textScaler: TextScaler.linear(scale),
    ),
    child: Scaffold(body: ListView(children: [child])),
  ),
);

NoticeRow row({
  bool unread = true,
  VoidCallback? onTap,
  String category = 'rate',
}) => NoticeRow(
  avatar: const ColoredBox(color: Colors.grey),
  name: '测试坛友',
  time: '17:40',
  text: '给你的帖子评分 +5',
  title: '本地测试帖子标题',
  category: category,
  scoreText: '+5',
  unread: unread,
  onTap: onTap,
);

TextSpan sentence(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('notice-sentence'))).textSpan!
        as TextSpan;

void main() {
  testWidgets(
    'notice sentence keeps one name and highlights the source score',
    (tester) async {
      await tester.pumpWidget(app(row()));
      await tester.pumpAndSettle();
      final text = sentence(tester);
      expect(text.toPlainText(), '测试坛友 给你的帖子评分');
      final score = tester.widget<Text>(find.text('+5'));
      expect(score.style!.color, AppTokens.light.accent);
      expect(score.style!.fontWeight, FontWeight.w600);
      final title = tester.widget<Text>(find.text('《本地测试帖子标题》'));
      expect(title.maxLines, 1);
      expect(title.style!.color, AppTokens.light.text2);
      expect(
        tester.getSize(find.byKey(const ValueKey('notice-avatar'))).width,
        NoticeTokens.avatar,
      );
      expect(find.byKey(const ValueKey('notice-kind')), findsOneWidget);
      expect(find.byKey(const ValueKey('notice-quote')), findsNothing);
      final decorations = tester.widgetList<DecoratedBox>(
        find.byType(DecoratedBox),
      );
      expect(
        decorations.where(
          (box) =>
              box.decoration is BoxDecoration &&
              (box.decoration as BoxDecoration).border != null,
        ),
        isEmpty,
      );
    },
  );

  testWidgets(
    'large rating keeps the complete score and ellipsizes the title',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        app(
          const NoticeRow(
            avatar: SizedBox(),
            name: 'muyu_42',
            time: '17:40',
            text: '评分了您的帖子　邪恶指数 +5',
            scoreText: '邪恶指数 +5',
            title: '用于测试完整分值和帖子标题省略效果的长标题',
            category: 'rate',
          ),
          scale: 2,
        ),
      );
      final action = find.byKey(const ValueKey('notice-sentence'));
      final score = find.byKey(const ValueKey('notice-score'));
      final title = find.byKey(const ValueKey('notice-title'));
      final scoreParagraph = tester.renderObject<RenderParagraph>(score);
      final titleParagraph = tester.renderObject<RenderParagraph>(title);
      expect(tester.widget<Text>(action).maxLines, 1);
      expect(sentence(tester).toPlainText(), 'muyu_42 评分了您的帖子');
      expect(scoreParagraph.text.toPlainText(), '邪恶指数 +5');
      expect(scoreParagraph.maxLines, 1);
      expect(scoreParagraph.didExceedMaxLines, isFalse);
      expect(titleParagraph.didExceedMaxLines, isTrue);
      expect(tester.widget<Text>(title).overflow, TextOverflow.ellipsis);
      expect(
        tester.getRect(score).top,
        greaterThan(tester.getRect(action).top),
      );
      expect(
        tester.getRect(title).left,
        greaterThan(tester.getRect(score).right),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'opening shrinks the dot while retaining the name weight and action',
    (tester) async {
      var opened = 0;
      await tester.pumpWidget(app(row(onTap: () => opened++)));
      await tester.pumpAndSettle();
      expect(
        (sentence(tester).children!.first as TextSpan).style!.fontWeight,
        FontWeight.w600,
      );
      await tester.tap(find.byType(NoticeRow));
      await tester.pump();
      expect(opened, 1);
      expect(find.byKey(NoticeRow.unreadDotKey), findsOneWidget);
      expect(
        (sentence(tester).children!.first as TextSpan).style!.fontWeight,
        FontWeight.w600,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(NoticeRow.unreadDotKey), findsNothing);
      expect(
        (sentence(tester).children!.first as TextSpan).style!.fontWeight,
        FontWeight.w600,
      );
      await tester.tap(find.byType(NoticeRow));
      await tester.pumpAndSettle();
      expect(opened, 2);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets('reduced motion clears unread without a running spring', (
    tester,
  ) async {
    await tester.pumpWidget(app(row(onTap: () {}), reduced: true));
    await tester.tap(find.byType(NoticeRow));
    await tester.pumpAndSettle();
    expect(find.byKey(NoticeRow.unreadDotKey), findsNothing);
    expect(
      (sentence(tester).children!.first as TextSpan).style!.fontWeight,
      FontWeight.w600,
    );
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('system notice uses a bell and only the system identity', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const NoticeRow(
          avatar: Text('不应出现的头像'),
          name: '不应出现的名字',
          time: '',
          text: '账号资料已更新',
          system: true,
          category: 'post',
        ),
      ),
    );
    expect(sentence(tester).toPlainText(), '系统 账号资料已更新');
    expect(find.byIcon(AppIcons.notification), findsOneWidget);
    expect(find.byKey(const ValueKey('notice-kind')), findsNothing);
    expect(find.textContaining('不应出现'), findsNothing);
  });

  testWidgets(
    'outgoing conversation preview uses a muted prefix and 48 avatar',
    (tester) async {
      await tester.pumpWidget(
        app(
          const NoticeRow(
            avatar: SizedBox(),
            name: '对方',
            time: '昨天',
            text: '收到，谢谢',
            conversation: true,
            isOutgoing: true,
            unread: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final preview = tester.widget<Text>(
        find.byKey(const ValueKey('notice-preview')),
      );
      expect(preview.textSpan!.toPlainText(), '你：收到，谢谢');
      expect(
        (preview.textSpan! as TextSpan).children!.first.style!.color,
        AppTokens.light.text3,
      );
      expect(preview.style!.color, AppTokens.light.text);
      expect(
        tester.getSize(find.byKey(const ValueKey('notice-avatar'))).width,
        48,
      );
      expect(find.byKey(const ValueKey('notice-kind')), findsNothing);
    },
  );

  for (final style in AppearanceStyle.values) {
    for (final brightness in Brightness.values) {
      testWidgets('notice fits narrow doubled text $style $brightness', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          app(
            const NoticeRow(
              avatar: SizedBox(),
              name: '测试坛友',
              time: '17:40',
              text: '在帖子中提到了您',
              title: '本地测试帖子标题',
              category: 'at',
            ),
            style: style,
            brightness: brightness,
            scale: 2,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('《本地测试帖子标题》'), findsOneWidget);
        expect(find.text('17:40'), findsOneWidget);
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('notice-sentence')))
              .maxLines,
          2,
        );
      });
    }
  }
}
