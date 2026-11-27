import 'dart:async';

import 'package:chh_app/attachments/attachment_controller.dart';
import 'package:chh_app/attachments/image_pipeline.dart';
import 'package:chh_app/attachments/image_platform.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/new_thread_page.dart';
import 'package:chh_app/parser/upload_parser.dart';
import 'package:chh_app/ui/app_button.dart';
import 'package:chh_app/widgets/attachment_bar.dart';
import 'package:chh_app/widgets/composer/composer_tool_strip.dart';
import 'package:chh_app/widgets/expressive_composer.dart';
import 'package:chh_app/ui/press.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 不产生真实文件:缩略图路径为空,图片栏显示占位
class _Platform implements ImagePlatform {
  final List<String> selected;

  const _Platform({this.selected = const []});

  @override
  Future<List<String>> pick(int max) async => selected.take(max).toList();

  @override
  Future<SourceImage> open(String uri) async => const SourceImage(
    handle: 1,
    width: 800,
    height: 600,
    format: SourceFormat.jpeg,
    size: 1000,
  );

  @override
  Future<EncodedImage> encode(
    int handle, {
    required int maxSide,
    required int quality,
    bool png = false,
  }) async => const EncodedImage('/nonexistent/thumb.jpg', 1000);

  @override
  Future<EncodedImage> original(int handle) async =>
      const EncodedImage('/nonexistent/thumb.jpg', 1000);

  @override
  Future<void> close(int handle) async {}

  @override
  Future<void> discard(String path) async {}
}

void main() {
  testWidgets('图片上传中不能发送;传完后只有图片也能发', (tester) async {
    final gate = Completer<UploadOutcome>();
    final images = AttachmentController(
      loadContext: () async => const UploadContext(uid: '1', hash: 'h'),
      pipeline: const ImagePipeline(_Platform(selected: ['content://photo'])),
      upload: (context, image) => gate.future,
    );
    addTearDown(images.dispose);
    final sent = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: ExpressiveComposer(
            title: '写回复',
            showReplyIcon: true,
            hintText: '回复内容',
            attachments: images,
            onSubmit: (text) async {
              sent.add(text);
              return const PostResult(PostResultKind.success, '已发布');
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    AppButton send() =>
        tester.widget<AppButton>(find.byKey(const ValueKey('composer-send')));

    final add = find.descendant(
      of: find.byType(ComposerToolStrip),
      matching: find.byKey(const ValueKey('attachment-add')),
    );
    expect(add, findsOneWidget);
    expect(tester.getSize(find.byType(AttachmentBar)).height, 0);
    expect(send().onPressed, isNull);

    await tester.tap(add);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('attachment-0')), findsOneWidget);
    expect(send().onPressed, isNull);

    gate.complete(const UploadSucceeded('31'));
    await tester.pump();
    await tester.pump();
    expect(images.aids, ['31']);
    expect(send().onPressed, isNotNull);

    send().onPressed!();
    await tester.pump();
    expect(sent, ['']);
  });

  group('图片横栏贴在键盘上方', () {
    const keyboard = 300.0;

    void withKeyboard(WidgetTester tester) {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
      addTearDown(tester.view.reset);
    }

    AttachmentController images({Future<UploadContext?> Function()? load}) {
      final c = AttachmentController(
        loadContext: load ?? () async => null,
        pipeline: const ImagePipeline(_Platform()),
        upload: (context, image) async => const UploadSucceeded('1'),
      );
      addTearDown(c.dispose);
      return c;
    }

    testWidgets('回复框', (tester) async {
      withKeyboard(tester);
      var uploadContextRequests = 0;
      final attachments = images(
        load: () async {
          uploadContextRequests++;
          return null;
        },
      )..add(['content://photo']);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: Scaffold(
            body: ExpressiveComposer(
              title: '写回复',
              showReplyIcon: true,
              hintText: '回复内容',
              attachments: attachments,
              onSubmit: (_) async =>
                  const PostResult(PostResultKind.success, ''),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final tray = find.byType(AttachmentBar);
      final strip = find.byType(ComposerToolStrip);
      expect(tester.getBottomLeft(tray).dy, tester.getTopLeft(strip).dy);
      expect(
        tester.getTopLeft(tray).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(find.byType(TextField)).dy),
      );
      expect(tester.getBottomLeft(strip).dy, 844 - keyboard);
      final thumb = find.descendant(
        of: find.byKey(const ValueKey('attachment-0')),
        matching: find.byType(ClipRRect),
      );
      expect(tester.getSize(thumb), const Size.square(58));
      expect(find.textContaining('点图片重试，或移除后再发送'), findsOneWidget);
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is PressScale && widget.semanticLabel == '重试上传这张图片',
        ),
      );
      await tester.pumpAndSettle();
      expect(uploadContextRequests, 2);

      // The visual badge overhangs the image but remains tappable.
      await tester.tap(
        find.byWidgetPredicate(
          (widget) => widget is PressScale && widget.semanticLabel == '移除图片',
        ),
      );
      await tester.pumpAndSettle();
      expect(attachments.items, isEmpty);
      expect(tester.getSize(tray).height, 0);
      expect(tester.getBottomLeft(strip).dy, 844 - keyboard);
    });

    testWidgets('发主题', (tester) async {
      withKeyboard(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: NewThreadPage(
            fid: 99992,
            forumName: '离线测试版块',
            loadForm: () async =>
                const PostForm(action: 'unused', formhash: 'fake'),
            onSubmit: (_, _, _) async =>
                const PostResult(PostResultKind.success, ''),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getBottomLeft(find.byType(AttachmentBar)).dy,
        844 - keyboard,
      );
    });
  });
}
