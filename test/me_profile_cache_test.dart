import 'dart:io';
import 'package:chh_app/data/me_profile_cache.dart';
import 'package:chh_app/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

const profile = UserProfile(
  uid: '42',
  name: 'fixture',
  credits: 100,
  threads: 3,
  replies: 4,
);
void main() {
  test('last account snapshot persists and loads before fresh data', () async {
    final dir = await Directory.systemTemp.createTemp('me-cache-test');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/me.json');
    final first = MeProfileCache();
    await first.attach(file);
    first.select('42');
    first.put(profile);
    await first.flush();
    final second = MeProfileCache()..select('42');
    await second.attach(file);
    expect(second.forUser('42')?.credits, 100);
    expect(second.forUser('43'), isNull);
    second.select('43');
    second.put(profile);
    await second.flush();
    expect(second.forUser('42'), isNull);
    expect(await file.exists(), isFalse);
  });
  test('partial data keeps last known counters without inventing zeros', () {
    final cache = MeProfileCache()..select('42');
    cache.put(profile);
    cache.put(const UserProfile(uid: '42', name: 'fixture', credits: 0));
    expect(cache.forUser('42')?.credits, 0);
    expect(cache.forUser('42')?.threads, 3);
    expect(cache.forUser('42')?.replies, 4);
  });
  test('logout clears snapshot and ignores a late old-account write', () async {
    final cache = MeProfileCache()..select('42');
    cache.put(profile);
    cache.select(null);
    cache.put(profile);
    expect(cache.forUser('42'), isNull);
  });
  test('a late disk read cannot replace newer live counters', () async {
    final dir = await Directory.systemTemp.createTemp('me-cache-test');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/me.json');
    await file.writeAsString('{"uid":"42","name":"old","credits":1}');
    final cache = MeProfileCache()..select('42');
    final load = cache.attach(file);
    cache.put(profile);
    await load;
    await cache.flush();
    expect(cache.forUser('42')?.credits, 100);
  });
  test(
    'logout before disk attachment cannot resurrect the saved identity',
    () async {
      final dir = await Directory.systemTemp.createTemp('me-cache-test');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/me.json');
      await file.writeAsString('{"uid":"42","name":"old","credits":1}');
      final cache = MeProfileCache()..select(null);
      await cache.attach(file);
      expect(cache.forUser('42'), isNull);
      expect(await file.exists(), isFalse);
    },
  );
  test('corrupt snapshots are cold caches, not fabricated counters', () async {
    final dir = await Directory.systemTemp.createTemp('me-cache-test');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/me.json');
    await file.writeAsString('{oops');
    final cache = MeProfileCache()..select('42');
    await cache.attach(file);
    expect(cache.forUser('42'), isNull);
  });
}
