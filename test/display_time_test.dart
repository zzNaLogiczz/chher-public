import 'package:chh_app/core/chh_urls.dart';
import 'package:chh_app/core/display_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 19, 9, 53);

  test('uses the relative, calendar, and yearly rules in order', () {
    for (final (raw, expected) in [
      ('2026-11-19 09:53', '刚刚'),
      ('2026-11-19 09:52:01', '刚刚'),
      ('2026-11-19 09:52', '1 分钟前'),
      ('2026-11-19 08:54', '59 分钟前'),
      ('今天 08:53', '08:53'),
      ('昨天 8:04', '昨天 08:04'),
      ('2026-11-4 21:39', '11月4日 21:39'),
      ('2025-11-12 23:34', '2025年11月12日'),
      ('2026/01/02', '1月2日'),
      ('2026年1月2日', '1月2日'),
    ]) {
      expect(
        formatDisplayTime(raw: raw, now: now),
        expected,
        reason: raw,
      );
    }
  });

  test('applies the appropriate precision to each context', () {
    const raw = '11-12 23:34';
    expect(formatDisplayTime(raw: raw, now: now), '11月12日 23:34');
    expect(
      formatDisplayTime(raw: raw, now: now, style: DisplayTimeStyle.list),
      '11月12日',
    );
    expect(
      formatDisplayTime(
        raw: '2026-11-19 09:53',
        now: now,
        style: DisplayTimeStyle.dateOnly,
      ),
      '2026年11月19日',
    );
    expect(
      formatDisplayTime(at: DateTime(2026, 11, 4, 21, 39), now: now),
      '11月4日 21:39',
    );
    expect(formatDisplayTime(raw: '2026-11-19', now: now), '11月19日');
  });

  test('source-relative times parse against the injected clock', () {
    for (final (raw, parsed, expected) in [
      ('刚刚', now, '刚刚'),
      ('30 秒前', DateTime(2026, 11, 19, 9, 52, 30), '刚刚'),
      ('半小时前', DateTime(2026, 11, 19, 9, 23), '30 分钟前'),
      ('2 分钟前', DateTime(2026, 11, 19, 9, 51), '2 分钟前'),
      ('1小时前', DateTime(2026, 11, 19, 8, 53), '08:53'),
      ('1天前', DateTime(2026, 11, 18, 9, 53), '昨天 09:53'),
      ('前天 21:39', DateTime(2026, 11, 17, 21, 39), '11月17日 21:39'),
      ('发表于 11-12 23:34', DateTime(2026, 11, 12, 23, 34), '11月12日 23:34'),
    ]) {
      expect(ChhUrls.parseTime(raw, now: now), parsed, reason: raw);
      expect(
        formatDisplayTime(raw: raw, now: now),
        expected,
        reason: raw,
      );
    }
  });

  test(
    'relative time takes precedence across midnight and year boundaries',
    () {
      final newYear = DateTime(2027, 1, 1, 0, 3);
      expect(formatDisplayTime(raw: '2026-12-31 23:59', now: newYear), '4 分钟前');
      expect(
        formatDisplayTime(raw: '2026-12-31 22:59', now: newYear),
        '昨天 22:59',
      );
      expect(
        formatDisplayTime(
          raw: '2026-12-31 23:59',
          style: DisplayTimeStyle.section,
          now: newYear,
        ),
        '昨天',
      );
    },
  );

  test('invalid or unknown source text survives unchanged', () {
    for (final raw in [
      '  未知时间  ',
      '2026-2-30 09:00',
      '2026年2-3',
      '今天 25:00',
      '99999999999999999天前',
      '标签 2026-11-19 08:00',
      'https://example.invalid/2026-11-19',
      '10:45',
      '',
    ]) {
      expect(ChhUrls.parseTime(raw, now: now), isNull, reason: raw);
      expect(
        formatDisplayTime(raw: raw, now: now),
        raw,
        reason: raw,
      );
    }
    expect(formatDisplayTime(now: now), '');
  });

  test('mixed metadata retains its author and unrecognized dates', () {
    expect(
      formatDisplayTime(
        raw: '2026-11-4 21:39 | 作者: 示例',
        now: now,
        embedded: true,
      ),
      '11月4日 21:39 | 作者: 示例',
    );
    const invalid = '2026-11-4 21:3 | 作者: 示例';
    expect(formatDisplayTime(raw: invalid, now: now, embedded: true), invalid);
  });
}
