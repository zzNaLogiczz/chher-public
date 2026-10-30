/// 外观偏好独立于账号,存储不可用时仍可切换。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'app_log.dart';
import 'app_paths.dart';

enum AppearanceMode {
  system('跟随系统', ThemeMode.system),
  light('浅色', ThemeMode.light),
  dark('深色', ThemeMode.dark);

  final String label;
  final ThemeMode themeMode;

  const AppearanceMode(this.label, this.themeMode);
}

class AppearanceController extends ChangeNotifier {
  final Future<Directory?> Function() _directory;
  AppearanceMode _mode = AppearanceMode.system;
  Future<void>? _loading;
  Future<void> _writes = Future<void>.value();
  int _revision = 0;
  bool _disposed = false;

  /// 注入偏好目录后不访问平台通道。
  AppearanceController({Future<Directory?> Function()? directory})
    : _directory = directory ?? (() => AppPaths.instance.subdir('prefs'));

  AppearanceMode get mode => _mode;

  Future<void> load() => _loading ??= _read();

  Future<void> _read() async {
    final revision = _revision;
    var stored = AppearanceMode.system;
    try {
      final directory = await _directory();
      if (directory != null) {
        final decoded = jsonDecode(
          await File('${directory.path}/appearance-v1.json').readAsString(),
        );
        if (decoded is Map && decoded['version'] == 1) {
          for (final mode in AppearanceMode.values) {
            if (decoded['mode'] == mode.name) stored = mode;
          }
        }
      }
    } catch (_) {
      // 缺失或损坏的偏好不阻断启动。
    }
    // 启动读取超时后,用户的新选择优先于迟到的磁盘数据。
    if (_disposed || revision != _revision || stored == _mode) return;
    _mode = stored;
    notifyListeners();
  }

  Future<void> set(AppearanceMode mode) {
    _revision++;
    if (_mode != mode) {
      _mode = mode;
      notifyListeners();
    }
    // 串行原子写,快速切换时最后一次选择必须最后落盘。
    return _writes = _writes.then((_) => _persist(mode));
  }

  Future<void> _persist(AppearanceMode mode) async {
    try {
      final directory = await _directory();
      if (directory == null) {
        AppLog.w('APPEARANCE', '外观偏好目录不可用');
        return;
      }
      await directory.create(recursive: true);
      final file = File('${directory.path}/appearance-v1.json');
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(
        jsonEncode({'version': 1, 'mode': mode.name}),
        flush: true,
      );
      await temporary.rename(file.path);
    } catch (_) {
      AppLog.w('APPEARANCE', '外观偏好保存失败');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
