import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'cached_net_image.dart';

/// Automatic previews have a pixel budget; explicit original viewing is separate.
const previewImagePixelBudget = 4 * 1024 * 1024;

/// Keep the requested aspect ratio and all image content while bounding decoding.
ui.TargetImageSize previewDecodeSize(
  int sourceWidth,
  int sourceHeight,
  ui.TargetImageSize requested,
) {
  final width =
      requested.width ??
      (requested.height == null
          ? sourceWidth
          : (sourceWidth * requested.height! / sourceHeight).round());
  final height =
      requested.height ?? (sourceHeight * width / sourceWidth).round();
  var w = width.clamp(1, sourceWidth);
  var h = height.clamp(1, sourceHeight);
  if (w * h > previewImagePixelBudget) {
    final scale = math.sqrt(previewImagePixelBudget / (w * h));
    w = math.max(1, (w * scale).floor());
    h = math.max(1, (h * scale).floor());
    // Very narrow images may reach the one-pixel lower bound on one axis.
    if (w * h > previewImagePixelBudget) {
      if (w > h) {
        w = previewImagePixelBudget ~/ h;
      } else {
        h = previewImagePixelBudget ~/ w;
      }
    }
  }
  return ui.TargetImageSize(width: w, height: h);
}

/// Retains ResizeImage's public sizing/key behavior and its outer error eviction.
class PreviewResizeImage extends ResizeImage {
  PreviewResizeImage(
    ChhCachedImage source, {
    int? width,
    int? height,
    ResizeImagePolicy policy = ResizeImagePolicy.exact,
  }) : super(
         ChhCachedImage(
           source.url,
           headers: source.headers,
           cacheVariant: (source.cacheVariant, 'preview-pixels-v1'),
         ),
         width: width,
         height: height,
         policy: policy,
       );

  @override
  ImageStreamCompleter loadImage(
    ResizeImageKey key,
    ImageDecoderCallback decode,
  ) => super.loadImage(key, (buffer, {getTargetSize}) {
    return decode(
      buffer,
      getTargetSize: (width, height) => previewDecodeSize(
        width,
        height,
        getTargetSize?.call(width, height) ?? const ui.TargetImageSize(),
      ),
    );
  });
}
