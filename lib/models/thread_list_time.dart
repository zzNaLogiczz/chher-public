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
    final at =
        (posted ? thread.createdAt : null)?.toLocal() ??
        (raw == null ? null : parseSiteTime(raw, now: clock));
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

  static String? _section(DateTime at, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    if (day == today) return '今天';
    if (day.isAfter(today)) return null;
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    return day == yesterday ? '昨天' : '更早';
  }
}
