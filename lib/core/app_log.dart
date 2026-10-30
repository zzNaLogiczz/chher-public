/// 应用内日志
///
/// 真机出问题时没有日志就只能靠猜。这里记请求与结果的摘要,支持查看、复制、导出。
///
/// 安全红线:**永不记录密码、Cookie 值、验证票据原文**。
/// 涉及敏感字段只记名称与长度,够定位问题就行。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'log_store.dart';

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

  LogStore? _store;
  Timer? _flushTimer;
  bool _notifyScheduled = false;

  /// 接线磁盘存储
  ///
  /// 路径解析是异步的,就绪前的日志只在内存环形缓冲里;这里把当前缓冲逐条补写进 store,
  /// 启动最早期的排障现场不丢。定时器只在接线后才存在,未接线(含测试)不留任何 Timer。
  static void attachStore(
    LogStore store, {
    Duration flushInterval = const Duration(seconds: 1),
  }) {
    final self = instance;
    self._flushTimer?.cancel();
    self._store = store;
    for (final entry in self._entries) {
      store.enqueue(_singleLine(entry));
    }
    self._flushTimer = Timer.periodic(flushInterval, (_) => store.flush());
  }

  @visibleForTesting
  static void detachStoreForTesting() {
    instance._flushTimer?.cancel();
    instance._flushTimer = null;
    instance._store = null;
  }

  /// 把队列里的日志写盘;未接线时立即完成
  static Future<void> flush() => instance._store?.flush() ?? Future.value();

  /// 是否已接线磁盘存储
  static bool get hasStore => instance._store != null;

  /// 已落盘的历史,旧的在前、流式读取;未接线时为空流
  static Stream<String> history() =>
      instance._store?.dump() ?? const Stream.empty();

  /// 流式写出磁盘历史,10MB 不会一次进内存;仅在未接线时退回内存缓冲
  ///
  /// 已接线但磁盘读不到时导出就是空的,不用内存冒充完整历史。
  static Future<void> writeFullLog(File file) async {
    await flush();
    final sink = file.openWrite();
    try {
      if (hasStore) {
        // addStream 带背压,磁盘读得再快也不会在写端堆积
        await sink.addStream(history().map((line) => utf8.encode('$line\n')));
      } else {
        sink.write(instance.dump());
      }
    } finally {
      await sink.close();
    }
  }

  /// store 按行存取且不检查内容,单行不变式由这里保证:内嵌换行会被读回成多条
  static final _lineBreak = RegExp(r'\r\n|\r|\n');

  static String _singleLine(LogEntry entry) =>
      entry.toString().replaceAll(_lineBreak, ' \\n ');

  void _add(LogLevel level, String tag, String message) {
    final entry = LogEntry(DateTime.now(), level, tag, message);
    // 测试包同时打到系统日志,连着电脑时可以实时看;正式包只留在应用内
    if (!kReleaseMode) debugPrint('CHH $entry');
    _entries.add(entry);
    if (_entries.length > capacity) {
      _entries.removeRange(0, _entries.length - capacity);
    }
    _store?.enqueue(_singleLine(entry));
    _scheduleNotify();
  }

  /// 同一轮事件循环内的多条日志合并成一次通知,避免日志页每条都重建
  void _scheduleNotify() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      notifyListeners();
    });
  }

  /// 同时清内存与磁盘
  void clear() {
    _entries.clear();
    _store?.clear();
    _scheduleNotify();
  }

  /// 导出成纯文本,新的在下面,直接可以贴给别人
  String dump() => _entries.map((e) => e.toString()).join('\n');

  /// 字段摘要:只给名称与长度,不给值
  ///
  /// 密码、验证票据、Cookie 一律不能进日志,但字段缺失或长度异常是重要线索。
  static String fields(Map<String, String> form) =>
      form.entries.map((e) => '${e.key}(${e.value.length})').join(' ');

  /// URL 摘要:不保留用户信息、片段或查询值;重复字段分别记录长度。
  static String url(Object? input) {
    try {
      final uri = Uri.parse('$input');
      final query = uri.queryParametersAll.entries
          .expand((e) => e.value.map((v) => '${e.key}(${v.length})'))
          .join(' ');
      return '${uri.path}${query.isEmpty ? '' : '?$query'}';
    } catch (_) {
      return '<invalid URL>';
    }
  }

  /// 引擎错误可能带完整 URL,沿用请求日志的脱敏规则后再截短。
  static String failureReason(Object? reason) {
    final text = '$reason'.replaceAllMapped(
      RegExp(r'''https?://[^\s<>"']+''', caseSensitive: false),
      (match) => url(match.group(0)),
    );
    return text.length > 200 ? text.substring(0, 200) : text;
  }

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
