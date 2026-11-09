import 'package:chh_app/design/theme.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/parser/thread_parser.dart';
import 'package:chh_app/widgets/image_grid.dart';
import 'package:chh_app/widgets/image_stack_gallery.dart';
import 'package:chh_app/widgets/post_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'thread_attachment_parser_test.dart'
    show attachment, attachmentImage, attachmentPost;

void main() {
  tearDown(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  for (final mode in ['首楼', '原楼层', '评论']) {
    for (final lazy in [false, true]) {
      testWidgets('$mode正文外附件可展示并进入图集，lazy=$lazy', (tester) async {
        final post = parseThread(
          attachmentPost(
            mode == '首楼' ? 1 : 2,
            body: null,
            extra: attachment(attachmentImage('1') + attachmentImage('2')),
          ),
          tid: 42,
        ).posts.single;
        final images = post.content.whereType<ImageBlock>().toList();
        final urls = images.map((image) => image.url).toList();
        expect(urls, [
          'https://example.invalid/1.jpg',
          'https://example.invalid/2.jpg',
        ]);
        final selectedIndex = lazy ? 1 : 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(Brightness.light),
            home: Scaffold(
              body: SingleChildScrollView(
                child: SizedBox(
                  width: 320,
                  child: lazy
                      ? PostCard.block(
                          post: post,
                          isOpening: mode == '首楼',
                          commentStyle: mode == '评论',
                          contentBlock: images[selectedIndex],
                          gallery: urls,
                          galleryIndex: selectedIndex,
                        )
                      : PostCard(
                          post: post,
                          isOpening: mode == '首楼',
                          commentStyle: mode == '评论',
                        ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (!lazy) {
          final stack = tester.widget<ImageStackGallery>(
            find.byType(ImageStackGallery),
          );
          expect(stack.urls, urls);
          expect(stack.gallery, urls);
          expect(stack.galleryStartIndex, 0);
        }
        final imageButton = lazy
            ? find.byWidgetPredicate(
                (widget) =>
                    widget is Semantics &&
                    widget.properties.label == '查看第 ${selectedIndex + 1} 张图片',
              )
            : find.byKey(const ValueKey('image-stack-stage'));
        expect(imageButton, findsOneWidget);
        await tester.tap(imageButton);
        await tester.pumpAndSettle();
        final viewer = tester.widget<ImageViewerPage>(
          find.byType(ImageViewerPage),
        );
        expect(viewer.urls, urls);
        expect(viewer.initialIndex, selectedIndex);
        expect(find.text('${selectedIndex + 1} / 2'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
