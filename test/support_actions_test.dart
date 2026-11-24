import 'dart:ui' as ui;

import 'package:chh_app/support/support_actions.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_android/url_launcher_android.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  const support = MethodChannel('chh/support');
  const launcher = BasicMessageChannel<Object?>(
    'dev.flutter.pigeon.url_launcher_android.UrlLauncherApi.launchUrl',
    StandardMessageCodec(),
  );
  const expectedUri =
      'alipays://platformapi/startapp?saId=10000007&qrcode='
      'https%3A%2F%2Fqr.alipay.com%2Ffkx1985781l1ncdyp1jkfaf';

  setUpAll(UrlLauncherAndroid.registerWith);
  tearDown(() {
    messenger.setMockMethodCallHandler(support, null);
    messenger.setMockDecodedMessageHandler(launcher, null);
  });

  test('支付宝跳转链接逐字符匹配规格', () {
    expect(alipayJumpUri().toString(), expectedUri);
    expect(alipayJumpUri().queryParameters['qrcode'], alipayCode);
  });

  test('支付宝打开成功或失败都通过外部启动通道返回', () async {
    for (final succeeds in [true, false]) {
      messenger.setMockDecodedMessageHandler(launcher, (message) async {
        expect(message, [expectedUri, <String, String>{}, false]);
        return [succeeds];
      });
      expect(await openAlipay(), succeeds);
    }
  });

  for (final (kind, moduleCount) in [
    (SupportCode.alipay, 33),
    (SupportCode.weChat, 37),
  ]) {
    test('${kind.label} 生成 1080 × 1200 PNG，模块纯黑且有 4 模块静区', () async {
      final bytes = await renderSaveImage(kind);
      expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      final image = await _decodePng(bytes);
      addTearDown(image.dispose);
      expect((image.width, image.height), (1080, 1200));
      final data = (await image.toByteData())!;
      int pixel(int x, int y) => data.getUint32((y * image.width + x) * 4);
      int darkPixels(int start, int end) {
        var count = 0;
        for (var y = start; y < end; y++) {
          for (var x = 0; x < image.width; x++) {
            final rgba = pixel(x, y);
            final color = ui.Color((rgba >> 8) | ((rgba & 0xff) << 24));
            if (color.computeLuminance() < .6) count++;
          }
        }
        return count;
      }

      expect(darkPixels(90, 160), greaterThan(200), reason: '标题应清晰可见');
      expect(darkPixels(1120, 1170), greaterThan(50), reason: '底部小字应清晰可见');
      const moduleSize = 20;
      const quiet = 4 * moduleSize;
      final left = (image.width - moduleCount * moduleSize) ~/ 2;
      final top = 610 - moduleCount * moduleSize ~/ 2;
      final right = left + moduleCount * moduleSize;
      final bottom = top + moduleCount * moduleSize;
      // The top-left finder pattern begins with a black module.
      expect(pixel(left, top), 0x000000ff);
      expect(pixel(left + moduleSize - 1, top + moduleSize - 1), 0x000000ff);
      for (var y = top - quiet; y < bottom + quiet; y++) {
        for (var x = left - quiet; x < right + quiet; x++) {
          final color = pixel(x, y);
          if (y < top || y >= bottom || x < left || x >= right) {
            if (color != 0xffffffff) {
              fail('quiet zone pixel ($x, $y) is nonwhite');
            }
          } else if (color != 0x000000ff && color != 0xffffffff) {
            fail('QR pixel ($x, $y) is neither black nor white');
          }
        }
      }
    });
  }

  test('牌面二维码包含墨色、着墨变化和透明区域', () async {
    final image = await renderInkQr(SupportCode.alipay);
    addTearDown(image.dispose);
    expect((image.width, image.height), (167, 167));
    final data = (await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    ))!;
    int pixel(int x, int y) => data.getUint32((y * image.width + x) * 4);
    final core = <int>{
      for (var y = 2; y < 5; y++)
        for (var x = 2; x < 5; x++) pixel(x, y),
    };
    expect(core.length, greaterThan(1));
    for (final color in core) {
      expect((color >> 8) & 255, greaterThan((color >> 24) & 255));
    }
    // The finder pattern leaves a transparent module separating its rings.
    expect(pixel(8, 8), 0);
    expect(pixel(2, 0) & 255, greaterThan(0));
    expect(pixel(2, 36) & 255, greaterThan(0));
  });

  test('两张存图依次传递 PNG 字节和对应文件名', () async {
    final names = <String>[];
    messenger.setMockMethodCallHandler(support, (call) async {
      expect(call.method, 'saveImage');
      final arguments = call.arguments as Map<Object?, Object?>;
      expect(arguments.keys, unorderedEquals(['bytes', 'displayName']));
      final bytes = arguments['bytes'] as Uint8List;
      expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      names.add(arguments['displayName'] as String);
      return true;
    });
    expect(await saveCodes(SupportCode.values), {
      SupportCode.alipay: SaveCodeResult.saved,
      SupportCode.weChat: SaveCodeResult.saved,
    });
    expect(names, ['Chhers-alipay.png', 'Chhers-wechat.png']);
  });

  test('存图返回每张的状态，包括权限拒绝和写入失败', () async {
    messenger.setMockMethodCallHandler(support, (call) async {
      final name = (call.arguments as Map)['displayName'];
      throw PlatformException(
        code: name == 'Chhers-alipay.png' ? 'save_failed' : 'permission_denied',
      );
    });
    expect(await saveCodes(SupportCode.values), {
      SupportCode.alipay: SaveCodeResult.failed,
      SupportCode.weChat: SaveCodeResult.permissionDenied,
    });
  });

  test('同一批存图只申请一次存储权限', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(support, (_) async {
      calls++;
      throw PlatformException(code: 'permission_denied');
    });
    expect(await saveCodes(SupportCode.values), {
      SupportCode.alipay: SaveCodeResult.permissionDenied,
      SupportCode.weChat: SaveCodeResult.permissionDenied,
    });
    expect(calls, 1);
  });

  for (final result in WeChatResult.values) {
    test('微信通道识别 ${result.name}', () async {
      messenger.setMockMethodCallHandler(support, (call) async {
        expect(call.method, 'openWeChatScan');
        expect(call.arguments, isNull);
        return result.name;
      });
      expect(await openWeChat(), result);
    });
  }
}

Future<ui.Image> _decodePng(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}
