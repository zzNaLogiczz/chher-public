import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

const alipayCode = 'https://qr.alipay.com/fkx1985781l1ncdyp1jkfaf';
const weChatCode =
    'wxp://f2f04v9BPAgybQPesbLA_qWPseeFDaeuLfT72VrVIjecZ0Guzk46qcUk72YyjNUdewZt';

enum SupportCode {
  alipay('支付宝', 'alipay', ui.Color(0xFF1D5BC6), ui.Color(0xFF1677FF)),
  weChat('微信', 'wechat', ui.Color(0xFF128548), ui.Color(0xFF07C160));

  const SupportCode(this.label, this._assetName, this.ink, this.brandColor);

  final String label;
  final String _assetName;
  final ui.Color ink;
  final ui.Color brandColor;

  String get displayName => 'Chhers-$_assetName.png';
  String get _assetPath => 'assets/support/qr_$_assetName.png';
}

enum SaveCodeResult { saved, permissionDenied, failed }

enum WeChatResult { scan, app, missing }

const _channel = MethodChannel('chh/support');
const _black = ui.Color(0xFF000000);
const _white = ui.Color(0xFFFFFFFF);

Uri alipayJumpUri() => Uri.parse(
  'alipays://platformapi/startapp?saId=10000007&qrcode='
  '${Uri.encodeComponent(alipayCode)}',
);

Future<bool> openAlipay() async {
  try {
    return await launchUrl(
      alipayJumpUri(),
      mode: LaunchMode.externalApplication,
    );
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}

/// Report each requested image independently so a partial save can be shown.
Future<Map<SupportCode, SaveCodeResult>> saveCodes(
  Iterable<SupportCode> kinds,
) async {
  final results = <SupportCode, SaveCodeResult>{};
  var permissionDenied = false;
  for (final kind in kinds.toSet()) {
    if (permissionDenied) {
      results[kind] = SaveCodeResult.permissionDenied;
      continue;
    }
    try {
      final bytes = await renderSaveImage(kind);
      final saved = await _channel.invokeMethod<bool>('saveImage', {
        'bytes': bytes,
        'displayName': kind.displayName,
      });
      results[kind] = saved == true
          ? SaveCodeResult.saved
          : SaveCodeResult.failed;
    } on PlatformException catch (error) {
      permissionDenied = error.code == 'permission_denied';
      results[kind] = permissionDenied
          ? SaveCodeResult.permissionDenied
          : SaveCodeResult.failed;
    } on MissingPluginException {
      results[kind] = SaveCodeResult.failed;
    } on StateError {
      results[kind] = SaveCodeResult.failed;
    }
  }
  return results;
}

Future<WeChatResult> openWeChat() async {
  try {
    return switch (await _channel.invokeMethod<String>('openWeChatScan')) {
      'scan' => WeChatResult.scan,
      'app' => WeChatResult.app,
      _ => WeChatResult.missing,
    };
  } on PlatformException {
    return WeChatResult.missing;
  } on MissingPluginException {
    return WeChatResult.missing;
  }
}

/// Export a white, opaque PNG with whole-pixel modules and a quiet zone.
Future<Uint8List> renderSaveImage(SupportCode kind) async {
  const width = 1080;
  const height = 1200;
  const modulePixels = 20;
  final modules = await _loadModules(kind);
  try {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)..drawColor(_white, ui.BlendMode.src);
    final size = modules.width * modulePixels.toDouble();
    canvas.drawImageRect(
      modules,
      ui.Rect.fromLTWH(
        0,
        0,
        modules.width.toDouble(),
        modules.height.toDouble(),
      ),
      ui.Rect.fromLTWH((width - size) / 2, 610 - size / 2, size, size),
      ui.Paint()
        ..filterQuality = ui.FilterQuality.none
        ..colorFilter = const ui.ColorFilter.mode(_black, ui.BlendMode.srcIn),
    );
    _drawCenteredText(
      canvas,
      '${kind.label} · 扫码支持 Chhers',
      44,
      90,
      width,
      kind.ink,
    );
    _drawCenteredText(
      canvas,
      'Chhers',
      28,
      1120,
      width,
      const ui.Color(0xFF8A817A),
    );
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(width, height);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw StateError('support_png_encoding');
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  } finally {
    modules.dispose();
  }
}

/// Bake the colored ink and letterpress edges once. The caller owns the image.
/// The face painter applies the shared paper texture over all printed elements.
Future<ui.Image> renderInkQr(
  SupportCode kind, {
  int pixelsPerModule = 5,
}) async {
  if (pixelsPerModule < 1) {
    throw ArgumentError.value(pixelsPerModule, 'pixelsPerModule');
  }
  final modules = await _loadModules(kind);
  try {
    final source = await modules.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (source == null) throw StateError('support_qr_pixels');
    final size = modules.width * pixelsPerModule;
    final pixels = Uint8List(size * size * 4);
    final random = math.Random(0);
    final ink = kind.ink.toARGB32();
    final red = (ink >> 16) & 255;
    final green = (ink >> 8) & 255;
    final blue = ink & 255;
    for (var y = 0; y < size; y++) {
      final row = (y ~/ pixelsPerModule) * modules.width;
      for (var x = 0; x < size; x++) {
        final coverage = source.getUint8((row + x ~/ pixelsPerModule) * 4 + 3);
        if (coverage == 0) continue;
        final alpha =
            (coverage *
                    (random.nextDouble() < .025
                        ? .55
                        : .84 + random.nextDouble() * .16))
                .floor();
        final offset = (y * size + x) * 4;
        pixels[offset] = (red * alpha / 255).round();
        pixels[offset + 1] = (green * alpha / 255).round();
        pixels[offset + 2] = (blue * alpha / 255).round();
        pixels[offset + 3] = alpha;
      }
    }

    // Pad the mask so the outermost modules retain their pressed edge.
    const padding = 1;
    final inkImage = await _decodeInkPixels(pixels, size);
    try {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      void silhouette(ui.Color color, double dy) => canvas.drawImage(
        inkImage,
        ui.Offset(padding.toDouble(), padding + dy),
        ui.Paint()
          ..filterQuality = ui.FilterQuality.low
          ..colorFilter = ui.ColorFilter.mode(color, ui.BlendMode.srcIn),
      );
      silhouette(_white.withValues(alpha: .85), .9);
      silhouette(const ui.Color(0xFF3A2A1A).withValues(alpha: .35), -.5);
      canvas.drawImage(
        inkImage,
        const ui.Offset(padding * 1.0, padding * 1.0),
        ui.Paint()..filterQuality = ui.FilterQuality.none,
      );
      final picture = recorder.endRecording();
      try {
        return await picture.toImage(size + 2 * padding, size + 2 * padding);
      } finally {
        picture.dispose();
      }
    } finally {
      inkImage.dispose();
    }
  } finally {
    modules.dispose();
  }
}

Future<ui.Image> _loadModules(SupportCode kind) async {
  final data = await rootBundle.load(kind._assetPath);
  final codec = await ui.instantiateImageCodec(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

Future<ui.Image> _decodeInkPixels(Uint8List pixels, int size) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
  try {
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: size,
      height: size,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    try {
      final codec = await descriptor.instantiateCodec();
      try {
        return (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor.dispose();
    }
  } finally {
    buffer.dispose();
  }
}

void _drawCenteredText(
  ui.Canvas canvas,
  String text,
  double fontSize,
  double top,
  int width,
  ui.Color color,
) {
  final paragraph =
      (ui.ParagraphBuilder(
              ui.ParagraphStyle(
                textAlign: ui.TextAlign.center,
                fontSize: fontSize,
              ),
            )
            ..pushStyle(ui.TextStyle(color: color))
            ..addText(text))
          .build()
        ..layout(ui.ParagraphConstraints(width: width.toDouble()));
  try {
    canvas.drawParagraph(paragraph, ui.Offset(0, top));
  } finally {
    paragraph.dispose();
  }
}
