import 'dart:convert';
import 'dart:io';

import 'package:chh_app/data/thread_read_index.dart';
import 'package:chh_app/di.dart';
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

  test('resumed does not flush; unattached state is safe', () async {
    final flusher = LifecycleFlusher();
    flusher.didChangeAppLifecycleState(AppLifecycleState.resumed);
    flusher.didChangeAppLifecycleState(AppLifecycleState.detached);
  });
}
