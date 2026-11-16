import 'dart:convert';
import 'dart:io';

import 'package:chh_app/attachments/image_save.dart';
import 'package:chh_app/data/image_disk_cache.dart';
import 'package:chh_app/widgets/cached_net_image.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('chh/image');
  const url = 'https://static.chiphell.com/save-fixture.png';
  final bytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
    '60e6kgAAAABJRU5ErkJggg==',
  );
  late Directory dir;
  late ImageDiskCache previous;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('chher-save-test-');
    previous = imageDiskCache;
    imageDiskCache = ImageDiskCache(dir);
    await imageDiskCache.write(url, bytes);
    downloadCount = 0;
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    imageDiskCache = previous;
    await dir.delete(recursive: true);
  });

  for (final saved in [true, false]) {
    test(
      'system save $saved preserves cached original and cleans lease',
      () async {
        File? leased;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              expect(call.method, 'save');
              leased = File((call.arguments as Map)['path'] as String);
              expect(await leased!.readAsBytes(), bytes);
              return saved;
            });
        expect(await saveForumImage(url), saved);
        expect(downloadCount, 0);
        expect(await leased!.exists(), isFalse);
        expect(await imageDiskCache.read(url), bytes);
      },
    );
  }

  test('system failure is propagated and original remains retryable', () async {
    File? leased;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          leased = File((call.arguments as Map)['path'] as String);
          throw PlatformException(code: 'save_failed');
        });
    await expectLater(saveForumImage(url), throwsA(isA<PlatformException>()));
    expect(await leased!.exists(), isFalse);
    expect(await imageDiskCache.read(url), bytes);
    expect(downloadCount, 0);
  });
}
