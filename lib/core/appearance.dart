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

  /// 缺省薄雾白(首次安装或更新后的初始风格);朱砂红作为新上线主题,
  /// 由红点引导(setttings 入口三级红点)吸引用户主动发现。
  AppearanceStyle _style = AppearanceStyle.misty;

  /// 用户是否已经进过设置页(朱砂红上线引导红点已消费)。
  /// 一旦置位持久化,后续安装更新也不再提示。
  bool _styleDotSeen = false;
  Future<void>? _loading;
  Future<void> _writes = Future<void>.value();
  int _revision = 0;
  bool _disposed = false;

  /// 注入偏好目录后不访问平台通道。
  AppearanceController({Future<Directory?> Function()? directory})
    : _directory = directory ?? (() => AppPaths.instance.subdir('prefs'));

  AppearanceMode get mode => _mode;

  AppearanceStyle get style => _style;

  bool get styleDotSeen => _styleDotSeen;

  Future<void> load() => _loading ??= _read();

  Future<void> _read() async {
    final revision = _revision;
    var stored = AppearanceMode.system;
    var storedStyle = AppearanceStyle.misty;
    var storedDotSeen = false;
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
          storedDotSeen = decoded['styleDotSeen'] == true;
        }
      }
    } catch (_) {
      // 缺失或损坏的偏好不阻断启动。
    }
    // 启动读取超时后,用户的新选择优先于迟到的磁盘数据。
    if (_disposed || revision != _revision) return;
    final changed =
        stored != _mode ||
        storedStyle != _style ||
        storedDotSeen != _styleDotSeen;
    _mode = stored;
    _style = storedStyle;
    _styleDotSeen = storedDotSeen;
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

  /// 进入设置页即消费朱砂红上线引导;置位后写盘,后续不再出现。
  Future<void> markStyleDotSeen() {
    _revision++;
    if (!_styleDotSeen) {
      _styleDotSeen = true;
      notifyListeners();
    }
    return _queueWrite();
  }

  /// 串行原子写,快速切换时最后一次选择必须最后落盘。
  /// mode/style/styleDotSeen 同文件,写当前三维的快照。
  Future<void> _queueWrite() {
    final mode = _mode;
    final style = _style;
    final styleDotSeen = _styleDotSeen;
    return _writes = _writes.then((_) => _persist(mode, style, styleDotSeen));
  }

  Future<void> _persist(
    AppearanceMode mode,
    AppearanceStyle style,
    bool styleDotSeen,
  ) async {
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
          'styleDotSeen': styleDotSeen,
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
