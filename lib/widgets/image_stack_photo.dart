import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';

import '../design/image_stack_tokens.dart';
import '../design/tokens.dart';
import '../design/typography.dart';

/// Small, preblurred pixels and a color sample from an already decoded photo.
/// No provider is resolved here; the gallery owns the original image request.
class PhotoAtmosphere {
  final Color color;
  final double strength;
  final Uint8List backdropBytes;

  const PhotoAtmosphere({
    required this.color,
    required this.strength,
    required this.backdropBytes,
  });

  static final _cache = <String, Future<PhotoAtmosphere>>{};

  static Future<PhotoAtmosphere> fromImage(String cacheKey, ui.Image image) {
    final cached = _cache.remove(cacheKey);
    if (cached != null) {
      _cache[cacheKey] = cached;
      return cached;
    }
    final future = _sample(image.clone());
    _cache[cacheKey] = future;
    if (_cache.length > ImageStackTokens.atmosphereCacheSize) {
      _cache.remove(_cache.keys.first);
    }
    // Failed processing can be retried after a later successful decode.
    future.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {
        if (identical(_cache[cacheKey], future)) _cache.remove(cacheKey);
      },
    );
    return future;
  }

  static Future<PhotoAtmosphere> _sample(ui.Image source) async {
    final scale =
        ImageStackTokens.sampleSize / math.max(source.width, source.height);
    final width = math.max(1, (source.width * scale).round());
    final height = math.max(1, (source.height * scale).round());
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawImageRect(
      source,
      Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..filterQuality = FilterQuality.low,
    );
    final picture = recorder.endRecording();
    late ui.Image small;
    try {
      small = await picture.toImage(width, height);
    } finally {
      source.dispose();
      picture.dispose();
    }
    late Uint8List pixels;
    try {
      pixels = (await small.toByteData())!.buffer.asUint8List();
    } finally {
      small.dispose();
    }
    final sample = sampleColor(pixels);
    final blurred = await compute(_blur, (pixels, width, height));
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      blurred,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final image = await completer.future;
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      return PhotoAtmosphere(
        color: sample.color,
        strength: sample.strength,
        backdropBytes: png!.buffer.asUint8List(),
      );
    } finally {
      image.dispose();
    }
  }

  /// Neutral pixels contribute to coverage but cannot tint the glow.
  @visibleForTesting
  static ({Color color, double strength}) sampleColor(Uint8List pixels) {
    var colorful = 0.0;
    var total = 0.0;
    final buckets = List.generate(12, (_) => List<double>.filled(4, 0));
    for (var i = 0; i + 3 < pixels.length; i += 4) {
      final alpha = pixels[i + 3] / 255;
      final r = pixels[i].toDouble();
      final g = pixels[i + 1].toDouble();
      final b = pixels[i + 2].toDouble();
      final max = math.max(r, math.max(g, b));
      final min = math.min(r, math.min(g, b));
      total += alpha;
      if (max < 24 || max - min < 24 || (max - min) / max < .18) continue;
      colorful += alpha;
      final range = max - min;
      final hue =
          (max == r
              ? (g - b) / range
              : max == g
              ? (b - r) / range + 2
              : (r - g) / range + 4) %
          6;
      final bucket = buckets[(hue * 2).floor().clamp(0, 11)];
      bucket[0] += alpha;
      bucket[1] += r * alpha;
      bucket[2] += g * alpha;
      bucket[3] += b * alpha;
    }
    final dominant = buckets.reduce((a, b) => a[0] >= b[0] ? a : b);
    return (
      color: colorful == 0
          ? ImageStackTokens.clear
          : Color.fromARGB(
              255,
              (dominant[1] / dominant[0]).round(),
              (dominant[2] / dominant[0]).round(),
              (dominant[3] / dominant[0]).round(),
            ),
      strength: total == 0 ? 0 : colorful / total,
    );
  }

  // Blur the 48px sample once, so dragging paints only an ordinary image.
  static Uint8List _blur((Uint8List, int, int) sample) {
    final (pixels, width, height) = sample;
    final sigma =
        ImageStackTokens.blurSigma *
        ImageStackTokens.sampleSize /
        ImageStackTokens.frameHeight;
    final radius = (sigma * 3).ceil();
    final weights = List<double>.generate(
      radius * 2 + 1,
      (i) => math.exp(-math.pow(i - radius, 2) / (2 * sigma * sigma)),
    );
    final sum = weights.reduce((a, b) => a + b);
    for (var i = 0; i < weights.length; i++) {
      weights[i] /= sum;
    }
    final horizontal = Float64List(pixels.length);
    final output = Uint8List(pixels.length);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        for (var k = -radius; k <= radius; k++) {
          final src = (y * width + (x + k).clamp(0, width - 1)) * 4;
          final dst = (y * width + x) * 4;
          for (var channel = 0; channel < 4; channel++) {
            horizontal[dst + channel] +=
                pixels[src + channel] * weights[k + radius];
          }
        }
      }
    }
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final dst = (y * width + x) * 4;
        final channels = List<double>.filled(4, 0);
        for (var k = -radius; k <= radius; k++) {
          final src = ((y + k).clamp(0, height - 1) * width + x) * 4;
          for (var channel = 0; channel < 4; channel++) {
            channels[channel] +=
                horizontal[src + channel] * weights[k + radius];
          }
        }
        final luminance =
            channels[0] * .2126 + channels[1] * .7152 + channels[2] * .0722;
        for (var channel = 0; channel < 3; channel++) {
          output[dst + channel] =
              (luminance +
                      (channels[channel] - luminance) *
                          ImageStackTokens.saturation)
                  .round()
                  .clamp(0, 255);
        }
        output[dst + 3] = channels[3].round().clamp(0, 255);
      }
    }
    return output;
  }
}

/// The picture well; its caller supplies the fixed frame and paper border.
class ImageStackPhoto extends StatelessWidget {
  final ImageProvider<Object> provider;
  final double ratio;
  final bool expanded;
  final bool compact;
  final Key? imageKey;
  final Object? heroTag;
  final PhotoAtmosphere? atmosphere;

  const ImageStackPhoto({
    super.key,
    required this.provider,
    required this.ratio,
    this.expanded = false,
    this.compact = false,
    this.imageKey,
    this.heroTag,
    this.atmosphere,
  });

  static bool fillsWell(double photoRatio, double wellRatio) =>
      (photoRatio / wellRatio - 1).abs() < ImageStackTokens.fillTolerance;

  static Rect mountedRect(Size well, double ratio) {
    const inset = ImageStackTokens.matInset;
    final availableW = math.max(1.0, well.width - inset * 2);
    final availableH = math.max(1.0, well.height - inset * 2);
    final w = math.min(availableW, availableH * ratio);
    final h = w / ratio;
    final top = (well.height - h) / 2;
    final up = math.min(ImageStackTokens.photoLift, math.max(0.0, top - inset));
    return Rect.fromLTWH((well.width - w) / 2, top - up, w, h);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final well = constraints.biggest;
        final long = !expanded && ratio < ImageStackTokens.longRatio;
        final fill = expanded || long || fillsWell(ratio, well.aspectRatio);
        final image = Image(
          key: imageKey,
          image: provider,
          fit: fill ? BoxFit.cover : BoxFit.contain,
          alignment: long ? Alignment.topCenter : Alignment.center,
          filterQuality: FilterQuality.low,
          gaplessPlayback: true,
          excludeFromSemantics: true,
          errorBuilder: (_, _, _) => ColoredBox(
            color: t.fill,
            child: Center(
              child: Text(
                '图片暂时无法加载',
                style: AppType.footnote.copyWith(color: t.text2),
              ),
            ),
          ),
        );
        final photo =
            heroTag != null && !MediaQuery.disableAnimationsOf(context)
            ? Hero(tag: heroTag!, child: image)
            : image;
        return ClipRRect(
          borderRadius: BorderRadius.circular(
            expanded
                ? ImageStackTokens.expandedRadius
                : compact
                ? ImageStackTokens.compactWellRadius
                : ImageStackTokens.wellRadius,
          ),
          child: ColoredBox(
            color: t.fill,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (!fill && atmosphere != null) ...[
                  Image.memory(
                    atmosphere!.backdropBytes,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.low,
                    excludeFromSemantics: true,
                    gaplessPlayback: true,
                  ),
                  ColoredBox(color: ImageStackTokens.mist(t)),
                ],
                if (fill)
                  photo
                else
                  Positioned.fromRect(
                    rect: mountedRect(well, ratio),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                          ImageStackTokens.photoRadius,
                        ),
                        boxShadow: ImageStackTokens.photoShadow,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          ImageStackTokens.photoRadius,
                        ),
                        child: photo,
                      ),
                    ),
                  ),
                if (long)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      height: ImageStackTokens.longLabelHeight,
                      alignment: Alignment.bottomCenter,
                      padding: const EdgeInsets.all(ImageStackTokens.matInset),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            ImageStackTokens.clear,
                            ImageStackTokens.ink.withValues(alpha: .7),
                          ],
                        ),
                      ),
                      child: Text(
                        '长图，点开看全部',
                        style: AppType.footnote.copyWith(
                          color: ImageStackTokens.onImage,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
