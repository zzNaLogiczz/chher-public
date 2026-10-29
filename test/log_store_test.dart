import 'dart:io';

import 'package:chh_app/core/log_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('chh-log-store-test-');
  });
  tearDown(() async => dir.delete(recursive: true));

  test('enqueue 不碰磁盘,flush 后才落盘', () async {
    final store = LogStore(dir);
    store.enqueue('第一行');
    expect(dir.listSync(), isEmpty);
    await store.flush();
    expect(await store.dump().join('\n'), contains('第一行'));
  });

  test('超过上限时淘汰最旧段,总量回落到上限内', () async {
    final store = LogStore(dir, segmentBytes: 1024, maxSegments: 3);
    for (var i = 0; i < 400; i++) {
      store.enqueue('行 $i ${'x' * 40}');
    }
    await store.flush();
    expect(dir.listSync().whereType<File>().length, lessThanOrEqualTo(3));
    final text = await store.dump().join('\n');
    expect(text, contains('行 399'));
    expect(text, isNot(contains('行 0 ')));
    expect(await store.totalBytes(), lessThanOrEqualTo(3 * 1024));
  });

  test('段序号单调递增且淘汰的序号不复用', () async {
    final store = LogStore(dir, segmentBytes: 256, maxSegments: 2);
    for (var i = 0; i < 40; i++) {
      store.enqueue('行 $i ${'x' * 40}');
    }
    await store.flush();
    final first = _segmentNumbers(dir);
    for (var i = 40; i < 80; i++) {
      store.enqueue('行 $i ${'x' * 40}');
    }
    await store.flush();
    final second = _segmentNumbers(dir);
    expect(second.length, lessThanOrEqualTo(2));
    expect(second.first, greaterThan(first.last));
  });

  test('重启后读回已落盘内容并接着写', () async {
    final first = LogStore(dir);
    first.enqueue('重启前');
    await first.flush();
    final second = LogStore(dir);
    second.enqueue('重启后');
    await second.flush();
    final lines = await LogStore(dir).dump().toList();
    expect(lines, ['重启前', '重启后']);
  });

  test('崩溃留下的残缺多字节不会吞掉同段后续行', () async {
    final store = LogStore(dir);
    store.enqueue('损坏前');
    await store.flush();
    final segment = File('${dir.path}/log-0.txt');
    // Truncated 3-byte sequence (first two bytes of a CJK char), as left by a crash.
    await segment.writeAsBytes([0xE4, 0xB8], mode: FileMode.append);
    final restarted = LogStore(dir);
    restarted.enqueue('损坏后');
    await restarted.flush();
    final lines = await restarted.dump().toList();
    expect(lines.first, '损坏前');
    expect(lines.last, endsWith('损坏后'));
  });

  test('只识别以路径分隔符起头的 log-<n>.txt', () async {
    await File('${dir.path}/xlog-5.txt').writeAsString('不是段文件\n');
    final store = LogStore(dir);
    expect(await store.totalBytes(), 0);
    expect(await store.dump().toList(), isEmpty);
  });

  test('目录不可写时 enqueue 与 flush 都不抛', () async {
    final store = LogStore(Directory('${dir.path}/gone'));
    store.enqueue('仍然可用');
    await store.flush();
    expect(await store.totalBytes(), 0);
    expect(await store.dump().toList(), isEmpty);
    await store.clear();
  });

  test('clear 清空磁盘与待写队列', () async {
    final store = LogStore(dir);
    store.enqueue('待清除');
    await store.flush();
    store.enqueue('未落盘');
    await store.clear();
    await store.flush();
    expect(await store.totalBytes(), 0);
    expect(await store.dump().toList(), isEmpty);
  });
}

List<int> _segmentNumbers(Directory dir) =>
    dir
        .listSync()
        .whereType<File>()
        .map(
          (f) => int.parse(RegExp(r'log-(\d+)\.txt$').firstMatch(f.path)![1]!),
        )
        .toList()
      ..sort();
