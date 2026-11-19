/// 日历日期、列表、详情和消息分组的显示规则。
enum DisplayTimeStyle { list, detail, dateOnly, section }

final _calendarTime = RegExp(
  r'^(?:(\d{4})([-/年]))?(\d{1,2})([-/月])(\d{1,2})(日)?'
  r'(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?$',
);
final _dayTime = RegExp(r'^(今天|昨天|前天)\s+(\d{1,2}):(\d{2})(?::(\d{2}))?$');
final _relativeTime = RegExp(r'^(\d+)\s*(秒|分钟|小时|天)前$');
final _sitePrefix = RegExp(r'^(?:发表于|最后发表)[:：]?\s*');

/// 明确含日期的混合元信息，如门户文章的「时间 | 作者」，只替换时间片段。
final _embeddedTime = RegExp(
  r'(?<![\d/-])\d{4}[-/年]\d{1,2}[-/月]\d{1,2}日?'
  r'(?:\s+\d{1,2}:\d{2}(?::\d{2})?|(?!\s+\d{1,2}:))(?![\d:/-])',
);

/// 未识别的源站文字原样保留。
String formatDisplayTime({
  String? raw,
  DateTime? at,
  DisplayTimeStyle style = DisplayTimeStyle.detail,
  DateTime? now,
  bool embedded = false,
}) {
  final clock = (now ?? DateTime.now()).toLocal();
  final parsed = raw == null ? null : _parse(raw, clock);
  if (embedded && raw != null && parsed == null && at == null) {
    return raw.replaceFirstMapped(
      _embeddedTime,
      (match) => formatDisplayTime(raw: match[0], style: style, now: clock),
    );
  }

  final local = at?.toLocal() ?? parsed?.at;
  if (local == null) {
    return style == DisplayTimeStyle.section ? '消息记录' : raw ?? '';
  }

  final date = '${local.month}月${local.day}日';
  if (style == DisplayTimeStyle.dateOnly) return '${local.year}年$date';

  final today = DateTime(clock.year, clock.month, clock.day);
  final yesterday = DateTime(clock.year, clock.month, clock.day - 1);
  final day = DateTime(local.year, local.month, local.day);
  if (style == DisplayTimeStyle.section) {
    if (day == today) return '今天';
    if (day == yesterday) return '昨天';
    return local.year == clock.year ? date : '${local.year}年$date';
  }

  final hasClock = parsed?.hasClock ?? true;
  if (hasClock) {
    final age = clock.difference(local);
    if (!age.isNegative && age < const Duration(hours: 1)) {
      return age.inMinutes == 0 ? '刚刚' : '${age.inMinutes} 分钟前';
    }
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    final time = '$hour:$minute';
    if (day == today) return time;
    if (day == yesterday) return '昨天 $time';
    if (style == DisplayTimeStyle.detail && local.year == clock.year) {
      return '$date $time';
    }
  }
  return local.year == clock.year ? date : '${local.year}年$date';
}

DateTime? parseSiteTime(String raw, {DateTime? now, bool embedded = false}) {
  final clock = (now ?? DateTime.now()).toLocal();
  final direct = _parse(raw, clock)?.at;
  if (direct != null || !embedded) return direct;
  final match = _embeddedTime.firstMatch(raw);
  return match == null ? null : _parse(match[0]!, clock)?.at;
}

({DateTime at, bool hasClock})? _parse(String raw, DateTime now) {
  final value = raw.trim().replaceFirst(_sitePrefix, '');
  final calendar = _calendarTime.firstMatch(value);
  if (calendar != null) {
    final year = calendar[1] == null ? now.year : int.parse(calendar[1]!);
    final separator = calendar[4];
    final yearSeparator = separator == '月' ? '年' : separator;
    if (calendar[2] != null && calendar[2] != yearSeparator) return null;
    if ((separator == '月') != (calendar[6] != null)) return null;
    final month = int.parse(calendar[3]!);
    final day = int.parse(calendar[5]!);
    final hour = int.parse(calendar[7] ?? '0');
    final minute = int.parse(calendar[8] ?? '0');
    final second = int.parse(calendar[9] ?? '0');
    final at = DateTime(year, month, day, hour, minute, second);
    // DateTime normalises invalid fields, so verify each one before displaying.
    if (at.year != year ||
        at.month != month ||
        at.day != day ||
        at.hour != hour ||
        at.minute != minute ||
        at.second != second) {
      return null;
    }
    return (at: at, hasClock: calendar[7] != null);
  }

  final namedDay = _dayTime.firstMatch(value);
  if (namedDay != null) {
    final hour = int.parse(namedDay[2]!);
    final minute = int.parse(namedDay[3]!);
    final second = int.parse(namedDay[4] ?? '0');
    if (hour > 23 || minute > 59 || second > 59) return null;
    final offset = const {'今天': 0, '昨天': 1, '前天': 2}[namedDay[1]]!;
    final at = DateTime(
      now.year,
      now.month,
      now.day - offset,
      hour,
      minute,
      second,
    );
    if (at.hour != hour || at.minute != minute || at.second != second) {
      return null;
    }
    return (at: at, hasClock: true);
  }

  if (value == '刚刚') return (at: now, hasClock: true);
  if (value == '半小时前') {
    return (at: now.subtract(const Duration(minutes: 30)), hasClock: true);
  }
  final relative = _relativeTime.firstMatch(value);
  final count = int.tryParse(relative?[1] ?? '');
  if (count == null) return null;
  final unit = const {'秒': 1, '分钟': 60, '小时': 3600, '天': 86400}[relative![2]]!;
  const maxAgeSeconds = 3153600000;
  if (count > maxAgeSeconds ~/ unit) return null;
  return (at: now.subtract(Duration(seconds: count * unit)), hasClock: true);
}
