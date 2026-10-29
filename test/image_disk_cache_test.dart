import 'dart:io';
import 'dart:typed_data';

import 'package:chh_app/data/image_disk_cache.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List bytes(int n) => Uint8List.fromList(List.filled(n, 7));

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('imgcache_test_'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('written bytes read back and hit counter increments', () async {
    final cache = ImageDiskCache(dir);
    await cache.write('https://static.chiphell.com/a.jpg', bytes(100));
    expect(
      await cache.read('https://static.chiphell.com/a.jpg'),
      hasLength(100),
    );
    expect(cache.hits, 1);
    expect(cache.misses, 0);
  });

  test('unknown url is a miss', () async {
    final cache = ImageDiskCache(dir);
    expect(await cache.read('https://static.chiphell.com/none.jpg'), isNull);
    expect(cache.misses, 1);
  });

  test('hit path performs no write (mtime untouched)', () async {
    final cache = ImageDiskCache(dir);
    const url = 'https://static.chiphell.com/a.jpg';
    await cache.write(url, bytes(100));
    final file = dir.listSync().whereType<File>().single;
    final before = file.statSync().modified;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await cache.read(url);
    expect(file.statSync().modified, before);
  });

  test('empty bytes are not persisted', () async {
    await ImageDiskCache(
      dir,
    ).write('https://static.chiphell.com/e.jpg', Uint8List(0));
    expect(dir.listSync(), isEmpty);
  });

  test('no temp files left and file names are safe', () async {
    final cache = ImageDiskCache(dir);
    await cache.write('https://a.com/../../x?y=1/2', bytes(10));
    final names = dir.listSync().map((e) => e.uri.pathSegments.last).toList();
    expect(names, hasLength(1));
    expect(names.single, isNot(contains('/')));
    expect(names.single, isNot(endsWith('.tmp')));
    expect(names.single, matches(RegExp(r'^[0-9a-f]{32}\.img$')));
  });

  test(
    'exceeding the ceiling evicts least recently used down to 90%',
    () async {
      final cache = ImageDiskCache(dir, maxBytes: 1000);
      for (var i = 0; i < 12; i++) {
        await cache.write('https://static.chiphell.com/$i.jpg', bytes(100));
      }
      expect(await cache.totalBytes(), lessThanOrEqualTo(900));
      expect(await cache.read('https://static.chiphell.com/0.jpg'), isNull);
      expect(await cache.read('https://static.chiphell.com/11.jpg'), isNotNull);
    },
  );

  test('a recent hit protects an entry from eviction', () async {
    final cache = ImageDiskCache(dir, maxBytes: 1000);
    for (var i = 0; i < 9; i++) {
      await cache.write('https://static.chiphell.com/$i.jpg', bytes(100));
    }
    expect(await cache.read('https://static.chiphell.com/0.jpg'), isNotNull);
    await cache.write('https://static.chiphell.com/9.jpg', bytes(100));
    expect(await cache.read('https://static.chiphell.com/0.jpg'), isNotNull);
    expect(await cache.read('https://static.chiphell.com/1.jpg'), isNull);
  });

  test('overwriting a url does not double count bytes', () async {
    final cache = ImageDiskCache(dir);
    await cache.write('https://static.chiphell.com/a.jpg', bytes(100));
    await cache.write('https://static.chiphell.com/a.jpg', bytes(60));
    expect(await cache.totalBytes(), 60);
  });

  test('a new instance rescans existing files', () async {
    await ImageDiskCache(
      dir,
    ).write('https://static.chiphell.com/a.jpg', bytes(100));
    final fresh = ImageDiskCache(dir);
    expect(await fresh.totalBytes(), 100);
    expect(
      await fresh.read('https://static.chiphell.com/a.jpg'),
      hasLength(100),
    );
  });

  test('a vanished file is a miss, not an error', () async {
    final cache = ImageDiskCache(dir);
    const url = 'https://static.chiphell.com/vanish.jpg';
    await cache.write(url, bytes(100));
    for (final f in dir.listSync().whereType<File>()) {
      f.deleteSync();
    }
    expect(await cache.read(url), isNull);
    expect(await cache.totalBytes(), 0);
  });

  test('null dir is a silent no-op', () async {
    final cache = ImageDiskCache(null);
    await cache.write('https://static.chiphell.com/a.jpg', bytes(100));
    expect(await cache.read('https://static.chiphell.com/a.jpg'), isNull);
    expect(await cache.totalBytes(), 0);
    await cache.clear();
  });

  test('clear empties the directory and resets the total', () async {
    final cache = ImageDiskCache(dir);
    await cache.write('https://static.chiphell.com/a.jpg', bytes(100));
    await cache.clear();
    expect(dir.listSync(), isEmpty);
    expect(await cache.totalBytes(), 0);
    expect(await cache.read('https://static.chiphell.com/a.jpg'), isNull);
  });

  test(
    'eviction does not delete a file re-written while it was queued',
    () async {
      final cache = ImageDiskCache(dir, maxBytes: 200);
      const a = 'https://static.chiphell.com/a.jpg';
      // Queue order: write A, write B (evicts A), write A again. The eviction's
      // delete job runs after the second write of A and must not remove it.
      final writes = [
        cache.write(a, bytes(100)),
        cache.write('https://static.chiphell.com/b.jpg', bytes(100)),
        cache.write(a, bytes(100)),
      ];
      await Future.wait(writes);
      // totalBytes drains the queue, including the background deletions.
      final total = await cache.totalBytes();
      final onDisk = dir.listSync().whereType<File>().fold<int>(
        0,
        (sum, f) => sum + f.lengthSync(),
      );
      expect(total, onDisk);
      expect(await cache.read(a), isNotNull);
    },
  );
}
