import 'dart:convert';
import 'dart:io';

import 'package:chh_app/core/app_paths.dart';
import 'package:chh_app/data/follow_index.dart';
import 'package:chh_app/data/thread_read_index.dart';
import 'package:chh_app/data/user_block_index.dart';
import 'package:chh_app/di.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('leaving the foreground flushes the read ledger', () async {
    final dir = await Directory.systemTemp.createTemp('chh-lifecycle-');
    final file = File('${dir.path}/threads-v1.json');
    await threadReadIndex.attach(file);
    threadReadIndex.markRead(7, 3);
    expect(file.existsSync(), isFalse);

    LifecycleFlusher().didChangeAppLifecycleState(AppLifecycleState.paused);
    // Far inside the 2 s debounce, so only the hook can have written it.
    for (var i = 0; i < 50 && !file.existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    final stored = jsonDecode(await file.readAsString())['threads'] as Map;
    expect(stored.containsKey('7'), isTrue);
    await dir.delete(recursive: true);
  });

  test('backgrounding retries writes for the selected account', () async {
    final dir = await Directory.systemTemp.createTemp('chh-account-flush-');
    const pathsChannel = MethodChannel('chh/update');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      pathsChannel,
      (_) async => {'filesDir': dir.path, 'cacheDir': dir.path},
    );
    AppPaths.resetForTesting();
    addTearDown(() async {
      await followIndex.setUid(null);
      await userBlockIndex.setUid(null);
      messenger.setMockMethodCallHandler(pathsChannel, null);
      AppPaths.resetForTesting();
      await dir.delete(recursive: true);
    });

    for (final name in ['follows', 'blocks']) {
      await Directory('${dir.path}/$name').create();
    }
    for (final uid in ['10', '20']) {
      await File('${dir.path}/follows/$uid').writeAsString('obstruction');
      await File('${dir.path}/blocks/$uid').writeAsString('obstruction');
      await followIndex.setUid(uid);
      await userBlockIndex.setUid(uid);
      expect(await followIndex.follow(uid: '42', name: uid), isFalse);
      expect(await userBlockIndex.block(uid: '43', name: uid), isFalse);
    }

    for (final uid in ['10', '20']) {
      await File('${dir.path}/follows/$uid').delete();
      await File('${dir.path}/blocks/$uid').delete();
    }
    final follow = File('${dir.path}/follows/20/follows-v1.json');
    final block = File('${dir.path}/blocks/20/users-v1.json');
    LifecycleFlusher().didChangeAppLifecycleState(AppLifecycleState.paused);
    for (
      var i = 0;
      i < 50 && !(follow.existsSync() && block.existsSync());
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(
      jsonDecode(await follow.readAsString())['users'].single['name'],
      '20',
    );
    expect(
      jsonDecode(await block.readAsString())['users'].single['name'],
      '20',
    );
    expect(await Directory('${dir.path}/follows/10').exists(), isFalse);
    expect(await Directory('${dir.path}/blocks/10').exists(), isFalse);
  });

  test('resumed does not flush; unattached state is safe', () async {
    final flusher = LifecycleFlusher();
    flusher.didChangeAppLifecycleState(AppLifecycleState.resumed);
    flusher.didChangeAppLifecycleState(AppLifecycleState.detached);
  });
}
