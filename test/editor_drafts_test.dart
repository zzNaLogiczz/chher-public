import 'dart:async';

import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/new_thread_page.dart';
import 'package:chh_app/widgets/composer_sheet.dart';
import 'package:chh_app/ui/app_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _composer(
  WidgetTester tester,
  Future<PostResult> Function(String) submit, {
  String? draftKey,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => ComposerSheet.show(
              context,
              onSubmit: submit,
              draftKey: draftKey,
            ),
            child: const Text('打开回复'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开回复'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('reply failure retains input and an in-flight tap submits once', (
    tester,
  ) async {
    final pending = Completer<PostResult>();
    var submits = 0;
    await _composer(tester, (text) {
      submits++;
      return pending.future;
    });
    await tester.enterText(find.byType(TextField), '要保留的回复草稿');
    await tester.pump();
    await tester.tap(find.text('发送'));
    await tester.pump();
    await tester.tap(find.text('发送中'));
    expect(submits, 1);
    pending.complete(const PostResult(PostResultKind.failed, '暂时无法回复'));
    await tester.pumpAndSettle();
    expect(find.byType(ComposerSheet), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '要保留的回复草稿',
    );
    expect(find.text('暂时无法回复'), findsOneWidget);
  });

  testWidgets('unknown reply result cannot be resubmitted blindly', (
    tester,
  ) async {
    var submits = 0;
    await _composer(tester, (_) async {
      submits++;
      return const PostResult(PostResultKind.unknown, 'unknown');
    });
    await tester.enterText(find.byType(TextField), '未确认的回复');
    await tester.pump();
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    expect(find.text('返回阅读确认'), findsOneWidget);
    expect(
      tester
          .widget<AppButton>(find.byKey(const ValueKey('composer-send')))
          .onPressed,
      isNull,
    );
    expect(submits, 1);
  });

  testWidgets('closing and reopening the same reply restores its own draft', (
    tester,
  ) async {
    await _composer(
      tester,
      (_) async => const PostResult(PostResultKind.success, ''),
      draftKey: 'test-draft-isolation',
    );
    await tester.enterText(find.byType(TextField), '关掉后继续写');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开回复'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '关掉后继续写',
    );
  });

  testWidgets('new topic without a preset category shows a placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: NewThreadPage(
          fid: 99992,
          forumName: '离线测试版块',
          loadForm: () async => const PostForm(
            action: 'unused',
            formhash: 'f',
            types: [
              ThreadType(typeid: 1010, name: 'ITX'),
              ThreadType(typeid: 1011, name: '水冷'),
            ],
          ),
          onSubmit: (title, body, type) async =>
              const PostResult(PostResultKind.failed, '离线'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('选择分类'), findsOneWidget);
    expect(find.text('ITX'), findsNothing);
  });

  testWidgets('new topic places Cancel left and renders a static destination', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: NewThreadPage(
          fid: 99991,
          forumName: '离线测试版块(新)',
          loadForm: () async => const PostForm(action: 'unused', formhash: 'f'),
          onSubmit: (title, body, type) async =>
              const PostResult(PostResultKind.failed, '离线'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final cancel = find.text('取消');
    final title = find.text('发表主题');
    final submit = find.text('发表');
    expect(tester.getCenter(cancel).dx, lessThan(tester.getCenter(title).dx));
    expect(
      tester.getCenter(submit).dx,
      greaterThan(tester.getCenter(title).dx),
    );
    expect(find.byTooltip('返回'), findsNothing);
    expect(tester.widget<Text>(cancel).style!.color, AppTokens.light.text2);
    final destination = find.text('发布到 离线测试版块');
    expect(tester.getTopLeft(destination).dx, 20);
    expect(
      tester
          .getSemantics(destination)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isFalse,
    );
    semantics.dispose();

    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    expect(fields[0].style!.fontSize, 22);
    expect(fields[0].style!.fontWeight, FontWeight.w600);
    expect(fields[1].style!.fontSize, 17);
    expect(fields[1].style!.fontWeight, FontWeight.w400);
    for (final field in fields) {
      expect(field.decoration!.hintStyle!.fontSize, field.style!.fontSize);
      expect(field.decoration!.hintStyle!.fontWeight, field.style!.fontWeight);
    }
  });

  testWidgets('system back and Cancel both preserve the topic draft', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => NewThreadPage(
                    fid: 99993,
                    forumName: '离线测试版块',
                    loadForm: () async =>
                        const PostForm(action: 'unused', formhash: 'fake'),
                  ),
                ),
              ),
              child: const Text('打开发帖页'),
            ),
          ),
        ),
      ),
    );
    final open = find.text('打开发帖页');
    await tester.tap(open);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '保留标题');
    await tester.enterText(find.byType(TextField).last, '保留正文');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(NewThreadPage), findsNothing);

    await tester.tap(open);
    await tester.pumpAndSettle();
    expect(find.text('保留标题'), findsOneWidget);
    expect(find.text('保留正文'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(NewThreadPage), findsNothing);
  });

  testWidgets(
    'new topic errors keep title and body without duplicate submission',
    (tester) async {
      final pending = Completer<PostResult>();
      var submits = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: NewThreadPage(
            fid: 99991,
            forumName: '离线测试版块',
            loadForm: () async =>
                const PostForm(action: 'unused', formhash: 'fake'),
            onSubmit: (title, body, type) {
              submits++;
              return pending.future;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), '保留的标题');
      await tester.enterText(find.byType(TextField).at(1), '保留的正文');
      await tester.pump();
      await tester.tap(find.text('发表'));
      await tester.pump();
      await tester.tap(find.text('发表中'));
      expect(submits, 1);
      pending.complete(const PostResult(PostResultKind.failed, '暂时无法发表'));
      await tester.pumpAndSettle();
      final fields = tester
          .widgetList<TextField>(find.byType(TextField))
          .toList();
      expect(fields[0].controller!.text, '保留的标题');
      expect(fields[1].controller!.text, '保留的正文');
      // 失败说明在正文和图片栏之后,列表按需构建,先滚过去
      await tester.scrollUntilVisible(
        find.text('暂时无法发表'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('暂时无法发表'), findsOneWidget);
      final failure =
          tester
                  .widget<DecoratedBox>(
                    find
                        .ancestor(
                          of: find.text('暂时无法发表'),
                          matching: find.byWidgetPredicate(
                            (widget) =>
                                widget is DecoratedBox &&
                                widget.decoration is ShapeDecoration,
                          ),
                        )
                        .first,
                  )
                  .decoration
              as ShapeDecoration;
      final shape = failure.shape as RoundedSuperellipseBorder;
      expect(shape.borderRadius.resolve(TextDirection.ltr).topLeft.x, 12);
    },
  );
}
