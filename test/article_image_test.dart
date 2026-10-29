import 'dart:async';

import 'package:chh_app/widgets/article_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _PendingImageProvider extends ImageProvider<Object> {
  final frame = Completer<ImageInfo>();

  @override
  Future<Object> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<Object>(this);

  @override
  ImageStreamCompleter loadImage(Object key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(frame.future);
}

void main() {
  testWidgets(
    'reserves height before any image bytes arrive, then keeps original ratio',
    (tester) async {
      final provider = _PendingImageProvider();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 320,
                  child: ArticleImage(
                    url: 'https://static.chiphell.com/pending.jpeg',
                    imageProvider: provider,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      // No frame or chunk event has been emitted. It must still occupy space
      // so the sliver cannot advance past all the unloaded pictures.
      expect(tester.getSize(find.byType(ArticleImage)), const Size(320, 240));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getSize(find.byType(ArticleImage)).height, 240);

      final image = (await tester.runAsync(
        () => createTestImage(width: 120, height: 240, cache: false),
      ))!;
      provider.frame.complete(ImageInfo(image: image));
      await tester.pump();
      await tester.pump();
      // A portrait image must expand to its natural 1:2 ratio, not remain
      // constrained to the loading placeholder or a cropped thumbnail.
      expect(tester.getSize(find.byType(ArticleImage)), const Size(320, 640));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
