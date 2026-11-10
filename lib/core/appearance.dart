/// 外观偏好独立于账号,存储不可用时仍可切换。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../design/tokens.dart';
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

  /// 1.0.8 已发布朱砂红;升级用户的存量偏好文件里没有 style 字段,
  /// 缺省保持朱砂红,不让老用户升级后界面突变。
  AppearanceStyle _style = AppearanceStyle.cinnabar;
  Future<void>? _loading;
  Future<void> _writes = Future<void>.value();
  int _revision = 0;
  bool _disposed = false;

  /// 注入偏好目录后不访问平台通道。
  AppearanceController({Future<Directory?> Function()? directory})
    : _directory = directory ?? (() => AppPaths.instance.subdir('prefs'));

  AppearanceMode get mode => _mode;

  AppearanceStyle get style => _style;

  Future<void> load() => _loading ??= _read();

  Future<void> _read() async {
    final revision = _revision;
    var stored = AppearanceMode.system;
    var storedStyle = AppearanceStyle.cinnabar;
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
          for (final style in AppearanceStyle.values) {
            if (decoded['style'] == style.name) storedStyle = style;
          }
        }
      }
    } catch (_) {
      // 缺失或损坏的偏好不阻断启动。
    }
    // 启动读取超时后,用户的新选择优先于迟到的磁盘数据。
    if (_disposed || revision != _revision) return;
    final changed = stored != _mode || storedStyle != _style;
    _mode = stored;
    _style = storedStyle;
    if (changed) notifyListeners();
  }

  Future<void> set(AppearanceMode mode) {
    _revision++;
    if (_mode != mode) {
      _mode = mode;
      notifyListeners();
    }
    return _queueWrite();
  }

  Future<void> setStyle(AppearanceStyle style) {
    _revision++;
    if (_style != style) {
      _style = style;
      notifyListeners();
    }
    return _queueWrite();
  }

  /// 串行原子写,快速切换时最后一次选择必须最后落盘。
  /// mode 与 style 同文件,写当前两维的快照。
  Future<void> _queueWrite() {
    final mode = _mode;
    final style = _style;
    return _writes = _writes.then((_) => _persist(mode, style));
  }

  Future<void> _persist(AppearanceMode mode, AppearanceStyle style) async {
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
        jsonEncode({
          'version': 1,
          'mode': mode.name,
          'style': style.name,
        }),
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
