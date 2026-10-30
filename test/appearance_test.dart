import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chh_app/core/app_log.dart';
import 'package:chh_app/core/appearance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late AppearanceController controller;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('chh-appearance-');
    controller = AppearanceController(directory: () async => directory);
  });

  tearDown(() {
    controller.dispose();
    directory.deleteSync(recursive: true);
  });

  File preference() => File('${directory.path}/appearance-v1.json');

  test('缺失文件默认跟随系统', () async {
    await controller.load();
    expect(controller.mode, AppearanceMode.system);
    expect(controller.mode.themeMode, ThemeMode.system);
  });

  test('先通知界面,原子写入后新实例恢复深色', () async {
    final notifications = <AppearanceMode>[];
    controller.addListener(() => notifications.add(controller.mode));
    final saving = controller.set(AppearanceMode.dark);
    expect(controller.mode, AppearanceMode.dark);
    expect(notifications, [AppearanceMode.dark]);
    await saving;

    expect(jsonDecode(await preference().readAsString()), {
      'version': 1,
      'mode': 'dark',
    });
    expect(await File('${preference().path}.tmp').exists(), isFalse);
    final restored = AppearanceController(directory: () async => directory);
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.mode, AppearanceMode.dark);
  });

  for (final payload in [
    '{broken',
    '[]',
    '{"version":2,"mode":"dark"}',
    '{"version":1,"mode":"unknown"}',
  ]) {
    test('损坏或不支持的偏好降级跟随系统: $payload', () async {
      await preference().writeAsString(payload);
      await controller.load();
      expect(controller.mode, AppearanceMode.system);
    });
  }

  test('目录不可用不抛异常,写入只记警告并保留界面', () async {
    final unavailable = AppearanceController(directory: () async => null);
    addTearDown(unavailable.dispose);
    await unavailable.load();
    expect(unavailable.mode, AppearanceMode.system);
    final before = AppLog.instance.entries.length;
    await expectLater(unavailable.set(AppearanceMode.dark), completes);
    expect(unavailable.mode, AppearanceMode.dark);
    expect(AppLog.instance.entries.length, greaterThan(before));
    expect(AppLog.instance.entries.last.level, LogLevel.warn);
  });

  test('目录解析或创建失败不抛异常', () async {
    final blocked = File('${directory.path}/blocked');
    await blocked.writeAsString('file');
    for (final resolve in <Future<Directory?> Function()>[
      () async => Directory(blocked.path),
      () async => throw const FileSystemException('unavailable'),
    ]) {
      final unavailable = AppearanceController(directory: resolve);
      addTearDown(unavailable.dispose);
      await unavailable.load();
      expect(unavailable.mode, AppearanceMode.system);
      await expectLater(unavailable.set(AppearanceMode.light), completes);
      expect(unavailable.mode, AppearanceMode.light);
    }
  });

  test('连续切换串行写入,最后一次选择在重启后保留', () async {
    await Future.wait([
      controller.set(AppearanceMode.dark),
      controller.set(AppearanceMode.system),
      controller.set(AppearanceMode.light),
    ]);
    final restored = AppearanceController(directory: () async => directory);
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.mode, AppearanceMode.light);
  });

  test('启动等待超时后继续使用系统,迟到的读取仍通知主题更新', () async {
    await preference().writeAsString('{"version":1,"mode":"dark"}');
    final pending = Completer<Directory?>();
    final delayed = AppearanceController(directory: () => pending.future);
    addTearDown(delayed.dispose);
    final notifications = <AppearanceMode>[];
    delayed.addListener(() => notifications.add(delayed.mode));
    final loading = delayed.load();
    await loading.timeout(Duration.zero, onTimeout: () {});
    expect(delayed.mode, AppearanceMode.system);
    pending.complete(directory);
    await loading;
    expect(delayed.mode, AppearanceMode.dark);
    expect(notifications, [AppearanceMode.dark]);
  });

  test('迟到的启动读取不能覆盖用户的新选择', () async {
    await preference().writeAsString('{"version":1,"mode":"dark"}');
    final pending = Completer<Directory?>();
    final delayed = AppearanceController(directory: () => pending.future);
    addTearDown(delayed.dispose);
    final loading = delayed.load();
    final saving = delayed.set(AppearanceMode.light);
    expect(delayed.mode, AppearanceMode.light);
    pending.complete(directory);
    await Future.wait([loading, saving]);
    expect(delayed.mode, AppearanceMode.light);
  });
}
