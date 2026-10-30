import 'dart:async';

import 'package:chh_app/network/serial_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('并发任务等待前一个完成再开始', () async {
    final queue = SerialQueue();
    final release = Completer<void>();
    final started = Completer<void>();
    final order = <String>[];
    final first = queue.run(() async {
      order.add('first start');
      started.complete();
      await release.future;
      order.add('first end');
      return 1;
    });
    final second = queue.run(() async {
      order.add('second');
      return 2;
    });
    await started.future;
    expect(order, ['first start']);
    release.complete();
    expect(await Future.wait([first, second]), [1, 2]);
    expect(order, ['first start', 'first end', 'second']);
  });

  test('异步或同步异常不阻塞后续任务', () async {
    final queue = SerialQueue();
    for (final asyncFailure in [true, false]) {
      final failed = queue.run<int>(() {
        if (asyncFailure) return Future<int>.error(StateError('fixture'));
        throw StateError('fixture');
      });
      final next = queue.run(() async => 42);
      await expectLater(failed, throwsStateError);
      expect(await next, 42);
    }
  });
}
