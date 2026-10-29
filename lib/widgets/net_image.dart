/// 站点图片
///
/// 图在 static.chiphell.com。必须带浏览器形态的请求头:
/// 之前门户封面用裸 Image.network,没带头,所以一张都加载不出来。
library;

import 'package:flutter/material.dart';
import 'expressive_controls.dart';

import '../core/chh_urls.dart';
import '../design/tokens.dart';

const Map<String, String> chhImageHeaders = {
  'User-Agent': ChhUrls.chromeUa,
  'Referer': ChhUrls.base,
};

/// Decode only the pixels a scrolling surface can display. One dimension keeps
/// the source aspect ratio; small sources are never upscaled by ResizeImage.
int boundedImageDecodeWidth(double logicalWidth, double devicePixelRatio) {
  final physical = logicalWidth * devicePixelRatio;
  if (!physical.isFinite || physical <= 0) return 1280;
  return ((physical / 64).ceil() * 64).clamp(64, 2048);
}

ImageProvider<Object> boundedNetworkImage(String url, int decodeWidth) =>
    ResizeImage.resizeIfNeeded(
      decodeWidth,
      null,
      NetworkImage(url, headers: chhImageHeaders),
    );

class NetImage extends StatelessWidget {
  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;

  /// Hero flights use a stable viewport-sized decode while their rect changes.
  final int? decodeWidth;

  const NetImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.decodeWidth,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final logicalWidth = width?.isFinite == true
            ? width!
            : constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        return RepaintBoundary(
          child: Image(
            image: boundedNetworkImage(
              url,
              decodeWidth ??
                  boundedImageDecodeWidth(
                    logicalWidth,
                    MediaQuery.devicePixelRatioOf(context),
                  ),
            ),
            fit: fit,
            width: width,
            height: height,
            gaplessPlayback: true,
            // 加载中先占位,避免瀑布流在图片到位时整列跳动
            frameBuilder: (context, child, frame, synchronous) =>
                synchronous || frame != null
                ? child
                : Container(height: height ?? 150, color: t.fill),
            errorBuilder: (context, _, _) => Container(
              height: height ?? 90,
              color: t.fill,
              alignment: Alignment.center,
              child: Icon(AppIcons.image, size: 18, color: t.text3),
            ),
          ),
        );
      },
    );
  }
}
