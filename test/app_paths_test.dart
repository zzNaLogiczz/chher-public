import 'dart:io';

import 'package:chh_app/core/app_paths.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('chh/update');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('chh-paths-'));
  tearDown(() {
    AppPaths.resetForTesting();
    messenger.setMockMethodCallHandler(channel, null);
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('通道不可用时返回 null,不抛异常', () async {
    final paths = AppPaths.forTesting();
    expect(await paths.files(), isNull);
    expect(await paths.cache(), isNull);
    expect(await paths.subdir('logs'), isNull);
  });

  test('注入目录后 subdir 创建并返回子目录', () async {
    final paths = AppPaths.forTesting(files: root, cache: root);
    final logs = await paths.subdir('logs');
    expect(logs!.existsSync(), isTrue);
    expect(logs.path, endsWith('/logs'));
  });

  test('inCache 选择缓存目录而非文件目录', () async {
    final files = Directory('${root.path}/f')..createSync();
    final cache = Directory('${root.path}/c')..createSync();
    final paths = AppPaths.forTesting(files: files, cache: cache);
    final dir = await paths.subdir('img', inCache: true);
    expect(dir!.path, '${cache.path}/img');
  });

  test('PlatformException 同样被吞掉返回 null', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => throw PlatformException(code: 'update_failed'),
    );
    expect(await AppPaths.forTesting().files(), isNull);
  });

  test('appInfo 只调一次,结果被复用', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'appInfo') {
        calls++;
        return {'filesDir': '${root.path}/f', 'cacheDir': '${root.path}/c'};
      }
      return null;
    });
    final paths = AppPaths.forTesting();
    final files = await paths.files();
    final cache = await paths.cache();
    await paths.files();
    expect(calls, 1);
    expect(files!.path, '${root.path}/f');
    expect(cache!.path, '${root.path}/c');
  });
}
