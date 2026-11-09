import 'models.dart';
import 'thread_sort.dart';

/// The displayed time and date section always describe the server's sort key.
/// A missing or unrecognised last-reply time must not become a creation time.
class ThreadListTime {
  final DateTime? at;
  final String? label;
  final String? section;

  const ThreadListTime._(this.at, this.label, this.section);

  factory ThreadListTime.of(
    ThreadSummary thread,
    ThreadSort sort, {
    DateTime? now,
  }) {
    final clock = (now ?? DateTime.now()).toLocal();
    final raw = thread.lastPostTimeRaw?.trim();
    final at = sort == ThreadSort.posted
        ? thread.createdAt
        : _parse(raw, clock);
    final local = at?.toLocal();
    final fallback = sort == ThreadSort.posted || raw == null || raw.isEmpty
        ? null
        : raw;
    return ThreadListTime._(
      local,
      local == null
          ? fallback
          : sort != ThreadSort.posted && raw != null && _dateOnly.hasMatch(raw)
          ? _dateLabel(local, clock)
          : _format(local, clock),
      sort.groupsByDate && local != null ? _section(local, clock) : null,
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _hm(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';

  static String _format(DateTime at, DateTime now) {
    if (_sameDay(at, now)) return _hm(at);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    if (_sameDay(at, yesterday)) return '昨天 ${_hm(at)}';
    return _dateLabel(at, now);
  }

  static String _dateLabel(DateTime at, DateTime now) => at.year == now.year
      ? '${at.month}-${at.day}'
      : '${at.year}-${at.month}-${at.day}';

  static String? _section(DateTime at, DateTime now) {
    if (_sameDay(at, now)) return '今天';
    final today = DateTime(now.year, now.month, now.day);
    if (at.isAfter(today)) return null; // Do not label a future date "更早".
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    return _sameDay(at, yesterday) ? '昨天' : '更早';
  }

  static final _dateOnly = RegExp(r'^\d{4}-\d{1,2}-\d{1,2}$');
  static final _absoluteTime = RegExp(
    r'^(\d{4})-(\d{1,2})-(\d{1,2})(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?$',
  );
  static final _dayTime = RegExp(r'^(今天|昨天|前天)\s+(\d{1,2}):(\d{2})$');
  static final _relativeTime = RegExp(r'^(\d+)\s*(秒|分钟|小时|天)前$');

  static DateTime? _parse(String? raw, DateTime now) {
    if (raw == null || raw.isEmpty) return null;
    final absolute = _absoluteTime.firstMatch(raw);
    if (absolute != null) {
      final fields = [
        for (var i = 1; i <= 6; i++) int.tryParse(absolute[i] ?? '0')!,
      ];
      final at = DateTime(
        fields[0],
        fields[1],
        fields[2],
        fields[3],
        fields[4],
        fields[5],
      );
      // DateTime normalises invalid source dates; those must stay source text.
      if (at.year != fields[0] ||
          at.month != fields[1] ||
          at.day != fields[2] ||
          at.hour != fields[3] ||
          at.minute != fields[4] ||
          at.second != fields[5]) {
        return null;
      }
      return at;
    }
    final dayTime = _dayTime.firstMatch(raw);
    if (dayTime != null) {
      final hour = int.parse(dayTime[2]!);
      final minute = int.parse(dayTime[3]!);
      if (hour > 23 || minute > 59) return null;
      final days = const {'今天': 0, '昨天': 1, '前天': 2}[dayTime[1]]!;
      return DateTime(now.year, now.month, now.day - days, hour, minute);
    }
    if (raw == '刚刚') return now;
    final relative = _relativeTime.firstMatch(raw);
    if (relative == null) return null;
    final count = int.tryParse(relative[1]!);
    if (count == null || count > 3153600000) return null;
    final duration = switch (relative[2]) {
      '秒' => Duration(seconds: count),
      '分钟' => Duration(minutes: count),
      '小时' => Duration(hours: count),
      _ => Duration(days: count),
    };
    return now.subtract(duration);
  }
}
