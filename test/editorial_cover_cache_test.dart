import 'dart:convert';
import 'dart:io';

import 'package:chh_app/data/editorial_cover_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late File file;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('chh-cover-test-');
    file = File('${directory.path}/covers.json');
  });
  tearDown(() async => directory.delete(recursive: true));

  test(
    'restores URLs after restarting and repeated values do not notify',
    () async {
      final first = EditorialCoverCache.forTesting(file);
      var notifications = 0;
      first.addListener(() => notifications++);
      await first.remember(42, 'https://static.chiphell.com/full.jpg');
      await first.remember(42, 'https://static.chiphell.com/full.jpg');
      expect(notifications, 1);
      final restarted = EditorialCoverCache.forTesting(file);
      await restarted.load();
      expect(restarted.lookup(42), 'https://static.chiphell.com/full.jpg');
      first.dispose();
      restarted.dispose();
    },
  );

  test('remembers newer values while loading and serializes writes', () async {
    await file.writeAsString(
      jsonEncode({
        'version': 1,
        'covers': {'42': 'https://static.chiphell.com/old.jpg'},
      }),
    );
    final cache = EditorialCoverCache.forTesting(file);
    final loading = cache.load();
    final first = cache.remember(42, 'https://static.chiphell.com/new.jpg');
    final second = cache.remember(
      43,
      'https://static.chiphell.com/another.jpg',
    );
    await Future.wait([loading, first, second]);
    expect(cache.lookup(42), 'https://static.chiphell.com/new.jpg');
    final stored = jsonDecode(await file.readAsString())['covers'] as Map;
    expect(stored['42'], endsWith('/new.jpg'));
    expect(stored['43'], endsWith('/another.jpg'));
    cache.dispose();
  });

  test('keeps 100 latest entries and rejects non-image URL schemes', () async {
    final cache = EditorialCoverCache.forTesting(file);
    await cache.remember(900, 'file:///private/data');
    await cache.remember(901, 'javascript:alert(1)');
    final writes = <Future<void>>[];
    for (var id = 1; id <= 105; id++) {
      writes.add(cache.remember(id, 'https://static.chiphell.com/$id.jpg'));
    }
    await Future.wait(writes);
    expect(cache.lookup(1), isNull);
    expect(cache.lookup(5), isNull);
    expect(cache.lookup(6), isNotNull);
    expect(cache.lookup(900), isNull);
    final stored = jsonDecode(await file.readAsString())['covers'] as Map;
    expect(stored.length, 100);
    expect(stored['105'], endsWith('/105.jpg'));
    cache.dispose();
  });

  test('malformed storage does not interrupt subsequent reuse', () async {
    await file.writeAsString('not valid json');
    final cache = EditorialCoverCache.forTesting(file);
    await cache.load();
    expect(cache.lookup(42), isNull);
    await cache.remember(42, 'https://static.chiphell.com/recovered.jpg');
    expect(cache.lookup(42), endsWith('/recovered.jpg'));
    expect(jsonDecode(await file.readAsString()), isA<Map>());
    cache.dispose();
  });
}
