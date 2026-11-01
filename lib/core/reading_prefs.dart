/// 阅读偏好独立于账号，存储不可用时仍可切换。
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'app_log.dart';
import 'app_paths.dart';

enum ReadingFontSize { xs, s, m, l, xl }

enum ReadingLineHeight { compact, standard, loose }

enum ReadingLayout { comfy, compact }

@immutable
class ReadingPrefs {
  final ReadingFontSize fontSize;
  final ReadingLineHeight lineHeight;
  final ReadingLayout layout;

  const ReadingPrefs({
    this.fontSize = ReadingFontSize.m,
    this.lineHeight = ReadingLineHeight.standard,
    this.layout = ReadingLayout.comfy,
  });

  ReadingPrefs copyWith({
    ReadingFontSize? fontSize,
    ReadingLineHeight? lineHeight,
    ReadingLayout? layout,
  }) => ReadingPrefs(
    fontSize: fontSize ?? this.fontSize,
    lineHeight: lineHeight ?? this.lineHeight,
    layout: layout ?? this.layout,
  );

  bool get isDefault => this == const ReadingPrefs();

  @override
  bool operator ==(Object other) =>
      other is ReadingPrefs &&
      other.fontSize == fontSize &&
      other.lineHeight == lineHeight &&
      other.layout == layout;

  @override
  int get hashCode => Object.hash(fontSize, lineHeight, layout);
}

class ReadingPrefsController extends ChangeNotifier {
  final Future<Directory?> Function() _directory;
  ReadingPrefs _prefs = const ReadingPrefs();
  Future<void>? _loading;
  Future<void> _writes = Future<void>.value();
  int _revision = 0;
  bool _disposed = false;

  /// 注入偏好目录后不访问平台通道。
  ReadingPrefsController({Future<Directory?> Function()? directory})
    : _directory = directory ?? (() => AppPaths.instance.subdir('prefs'));

  ReadingPrefs get prefs => _prefs;

  Future<void> load() => _loading ??= _read();

  Future<void> _read() async {
    final revision = _revision;
    var stored = const ReadingPrefs();
    try {
      final directory = await _directory();
      if (directory != null) {
        final decoded = jsonDecode(
          await File('${directory.path}/reading-v1.json').readAsString(),
        );
        if (decoded is Map && decoded['version'] == 1) {
          stored = ReadingPrefs(
            fontSize: ReadingFontSize.values.byName(
              decoded['fontSize'] as String,
            ),
            lineHeight: ReadingLineHeight.values.byName(
              decoded['lineHeight'] as String,
            ),
            layout: ReadingLayout.values.byName(decoded['layout'] as String),
          );
        }
      }
    } catch (_) {
      // 缺失或损坏的偏好不阻断启动。
    }
    // 启动读取超时后,用户的新选择优先于迟到的磁盘数据。
    if (_disposed || revision != _revision || stored == _prefs) return;
    _prefs = stored;
    notifyListeners();
  }

  Future<void> set(ReadingPrefs prefs) {
    _revision++;
    if (_prefs != prefs) {
      _prefs = prefs;
      notifyListeners();
    }
    // 串行原子写,快速切换时最后一次选择必须最后落盘。
    return _writes = _writes.then((_) => _persist(prefs));
  }

  Future<void> reset() => set(const ReadingPrefs());

  Future<void> _persist(ReadingPrefs prefs) async {
    try {
      final directory = await _directory();
      if (directory == null) {
        AppLog.w('READING', '阅读偏好目录不可用');
        return;
      }
      await directory.create(recursive: true);
      final file = File('${directory.path}/reading-v1.json');
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(
        jsonEncode({
          'version': 1,
          'fontSize': prefs.fontSize.name,
          'lineHeight': prefs.lineHeight.name,
          'layout': prefs.layout.name,
        }),
        flush: true,
      );
      await temporary.rename(file.path);
    } catch (_) {
      AppLog.w('READING', '阅读偏好保存失败');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
