import '../core/display_time.dart';
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
    final posted = sort == ThreadSort.posted;
    final raw = posted ? thread.createdAtRaw : thread.lastPostTimeRaw;
    final at = _sortTime(thread, posted, raw, clock);
    final label = formatDisplayTime(
      raw: raw,
      at: at,
      style: DisplayTimeStyle.list,
      now: clock,
    );
    return ThreadListTime._(
      at,
      label.trim().isEmpty ? null : label,
      sort.groupsByDate && at != null ? _section(at, clock) : null,
    );
  }

  /// Grouping visits every thread, while only mounted rows need display labels.
  static String? Function(ThreadSummary)? sectionLabels(
    ThreadSort sort, {
    required DateTime now,
  }) {
    if (!sort.groupsByDate) return null;
    final clock = now.toLocal();
    final posted = sort == ThreadSort.posted;
    final today = DateTime(clock.year, clock.month, clock.day);
    final yesterday = DateTime(clock.year, clock.month, clock.day - 1);
    final tomorrow = DateTime(clock.year, clock.month, clock.day + 1);
    final labels = <(DateTime?, String?), String?>{};
    return (thread) {
      final raw = posted ? thread.createdAtRaw : thread.lastPostTimeRaw;
      final key = (posted ? thread.createdAt : null, raw);
      return labels.putIfAbsent(key, () {
        final at = _sortTime(thread, posted, raw, clock);
        if (at == null || !at.isBefore(tomorrow)) return null;
        if (!at.isBefore(today)) return '今天';
        return at.isBefore(yesterday) ? '更早' : '昨天';
      });
    };
  }

  static DateTime? _sortTime(
    ThreadSummary thread,
    bool posted,
    String? raw,
    DateTime clock,
  ) =>
      (posted ? thread.createdAt : null)?.toLocal() ??
      (raw == null ? null : parseSiteTime(raw, now: clock));

  static String? _section(DateTime at, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    if (day == today) return '今天';
    if (day.isAfter(today)) return null;
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    return day == yesterday ? '昨天' : '更早';
  }
}
