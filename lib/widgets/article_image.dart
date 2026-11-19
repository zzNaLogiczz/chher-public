/// Article images reserve space until the first decoded frame arrives.
/// A network stream can report no chunk progress before it has any pixels;
/// using loadingBuilder alone allows an intrinsic-height image to collapse.
library;

import 'package:flutter/material.dart';
import '../design/typography.dart';
import '../design/image_tokens.dart';

import '../design/tokens.dart';
import 'chhers_loader.dart';
import 'chhers_loading_transition.dart';
import 'net_image.dart';

class ArticleImage extends StatelessWidget {
  final String url;

  /// Allows tests to hold the image stream before its first decoded frame.
  @visibleForTesting
  final ImageProvider<Object>? imageProvider;

  const ArticleImage({super.key, required this.url, this.imageProvider});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        return RepaintBoundary(
          child: Image(
            image:
                imageProvider ??
                boundedNetworkImage(
                  url,
                  boundedImageDecodeWidth(
                    width,
                    MediaQuery.devicePixelRatioOf(context),
                  ),
                ),
            color: t.isDark ? ImageTokens.darkTint : null,
            colorBlendMode: BlendMode.modulate,
            width: double.infinity,
            fit: BoxFit.fitWidth,
            gaplessPlayback: true,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded) return child;
              return ChhersLoadingTransition(
                size: ChhersLoaderSize.list,
                placeholderBuilder: (indicator) => AspectRatio(
                  aspectRatio: 4 / 3,
                  child: ColoredBox(
                    color: t.fill,
                    child: Center(child: indicator),
                  ),
                ),
                child: frame == null ? null : child,
              );
            },
            errorBuilder: (context, error, stack) => AspectRatio(
              aspectRatio: 4 / 3,
              child: ColoredBox(
                color: t.fill,
                child: Center(
                  child: Text(
                    '图片暂时无法加载',
                    style: TextStyle(
                      fontSize: AppType.sizeFootnote,
                      color: t.text2,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
