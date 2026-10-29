/// 应用内日志
///
/// 真机出问题时没有日志就只能靠猜。这里记请求与结果的摘要,支持查看、复制、导出。
///
/// 安全红线:**永不记录密码、Cookie 值、验证票据原文**。
/// 涉及敏感字段只记名称与长度,够定位问题就行。
library;

import 'package:flutter/foundation.dart';

enum LogLevel { info, warn, error }

@immutable
class LogEntry {
  final DateTime at;
  final LogLevel level;
  final String tag;
  final String message;

  const LogEntry(this.at, this.level, this.tag, this.message);

  String get timeText {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
  }

  String get levelMark => switch (level) {
    LogLevel.info => 'I',
    LogLevel.warn => 'W',
    LogLevel.error => 'E',
  };

  @override
  String toString() => '$timeText $levelMark [$tag] $message';
}

class AppLog extends ChangeNotifier {
  AppLog._();

  static final AppLog instance = AppLog._();

  /// 环形缓冲:只留最近若干条,避免长时间运行吃内存
  static const int capacity = 600;

  final List<LogEntry> _entries = [];

  List<LogEntry> get entries => List.unmodifiable(_entries);

  bool get isEmpty => _entries.isEmpty;

  static void i(String tag, String message) =>
      instance._add(LogLevel.info, tag, message);

  static void w(String tag, String message) =>
      instance._add(LogLevel.warn, tag, message);

  static void e(String tag, String message) =>
      instance._add(LogLevel.error, tag, message);

  void _add(LogLevel level, String tag, String message) {
    final entry = LogEntry(DateTime.now(), level, tag, message);
    // 测试包同时打到系统日志,连着电脑时可以实时看;正式包只留在应用内
    if (!kReleaseMode) debugPrint('CHH $entry');
    _entries.add(entry);
    if (_entries.length > capacity) {
      _entries.removeRange(0, _entries.length - capacity);
    }
    notifyListeners();
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }

  /// 导出成纯文本,新的在下面,直接可以贴给别人
  String dump() => _entries.map((e) => e.toString()).join('\n');

  /// 字段摘要:只给名称与长度,不给值
  ///
  /// 密码、验证票据、Cookie 一律不能进日志,但字段缺失或长度异常是重要线索。
  static String fields(Map<String, String> form) =>
      form.entries.map((e) => '${e.key}(${e.value.length})').join(' ');

  /// 响应摘要:状态、长度、去标签后的开头
  static String response(int status, String body, {int head = 160}) {
    final text = body
        .replaceAll(
          RegExp(r'<script[\s\S]*?</script>', caseSensitive: false),
          ' ',
        )
        .replaceAll(
          RegExp(r'<style[\s\S]*?</style>', caseSensitive: false),
          ' ',
        )
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'[\s ]+'), ' ')
        .trim();
    final cut = text.length > head ? '${text.substring(0, head)}…' : text;
    return 'status=$status len=${body.length} $cut';
  }
}
