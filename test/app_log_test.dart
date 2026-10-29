import 'dart:io';

import 'package:chh_app/core/app_log.dart';
import 'package:chh_app/core/log_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    AppLog.detachStoreForTesting();
    AppLog.instance.clear();
  });

  test('未接线时日志只在内存,不抛异常也不起定时器', () {
    AppLog.i('T', '仅内存');
    expect(AppLog.instance.dump(), contains('仅内存'));
    // 测试结束若有未取消定时器,flutter_test 会报 pending timer
  });

  test('接线时把已有内存缓冲补写进 store', () async {
    final dir = await Directory.systemTemp.createTemp('chh-applog-');
    addTearDown(() => dir.delete(recursive: true));
    AppLog.i('BOOT', '接线前就产生的日志');
    AppLog.attachStore(LogStore(dir));
    await AppLog.flush();
    expect(await AppLog.history().join('\n'), contains('接线前就产生的日志'));
  });

  test('同一帧内多条日志只通知一次', () async {
    var notifications = 0;
    void listener() => notifications++;
    AppLog.instance.addListener(listener);
    addTearDown(() => AppLog.instance.removeListener(listener));
    for (var i = 0; i < 20; i++) {
      AppLog.i('T', '第 $i 条');
    }
    await Future<void>.delayed(Duration.zero);
    expect(notifications, lessThan(20));
    expect(notifications, greaterThan(0));
  });

  test('落盘后内存环形缓冲容量仍是硬上限', () {
    for (var i = 0; i < AppLog.capacity + 200; i++) {
      AppLog.i('T', '第 $i 条');
    }
    expect(AppLog.instance.entries.length, AppLog.capacity);
  });

  test('clear 同时清内存与磁盘', () async {
    final dir = await Directory.systemTemp.createTemp('chh-applog-clear-');
    addTearDown(() => dir.delete(recursive: true));
    AppLog.attachStore(LogStore(dir));
    AppLog.i('T', '待清除');
    await AppLog.flush();
    AppLog.instance.clear();
    await AppLog.flush();
    expect(AppLog.instance.isEmpty, isTrue);
    expect(await AppLog.history().toList(), isEmpty);
  });

  test('含换行的消息落盘后仍是单行', () async {
    final dir = await Directory.systemTemp.createTemp('chh-applog-nl-');
    addTearDown(() => dir.delete(recursive: true));
    AppLog.attachStore(LogStore(dir));
    AppLog.e('T', '第一行\n第二行\r\n第三行\r第四行');
    await AppLog.flush();
    final lines = await AppLog.history().toList();
    expect(lines, hasLength(1));
    expect(lines.single, allOf(contains('第一行'), contains('第四行')));
  });

  test('未接线时 history 为空流', () async {
    AppLog.i('T', 'x');
    expect(await AppLog.history().toList(), isEmpty);
  });

  test('接线后的新日志会被定时 flush 落盘', () async {
    final dir = await Directory.systemTemp.createTemp('chh-applog-timer-');
    addTearDown(() => dir.delete(recursive: true));
    AppLog.attachStore(
      LogStore(dir),
      flushInterval: const Duration(milliseconds: 20),
    );
    AppLog.i('T', '靠定时器落盘');
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(await AppLog.history().join('\n'), contains('靠定时器落盘'));
  });
}
