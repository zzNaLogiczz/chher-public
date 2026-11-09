import 'package:chh_app/models/models.dart';
import 'package:chh_app/models/thread_list_time.dart';
import 'package:chh_app/models/thread_sort.dart';
import 'package:flutter_test/flutter_test.dart';

ThreadSummary thread({DateTime? createdAt, String? last}) => ThreadSummary(
  tid: 1,
  title: '时间测试',
  author: '作者',
  createdAt: createdAt,
  replies: 3,
  views: 20,
  lastPostTimeRaw: last,
);

void main() {
  final now = DateTime(2026, 11, 4, 14, 30);
  test('reply sorting displays last reply while publication uses creation', () {
    final t = thread(
      createdAt: DateTime(2025, 8, 2, 9),
      last: '2026-11-4 13:02:30',
    );
    for (final sort in [
      ThreadSort.latest,
      ThreadSort.replies,
      ThreadSort.views,
    ]) {
      final time = ThreadListTime.of(t, sort, now: now);
      expect(time.label, '13:02');
      expect(time.at, DateTime(2026, 11, 4, 13, 2, 30));
      expect(time.section, sort == ThreadSort.latest ? '今天' : null);
    }
    final posted = ThreadListTime.of(t, ThreadSort.posted, now: now);
    expect(posted.label, '2025-8-2');
    expect(posted.section, '更早');
  });

  test(
    'today yesterday this year and previous years have distinct formats',
    () {
      for (final (raw, label, section) in [
        ('2026-11-4 09:05', '09:05', '今天'),
        ('2026-11-3 23:59', '昨天 23:59', '昨天'),
        ('2026-10-31 11:30', '10-31', '更早'),
        ('2025-12-31 23:59', '2025-12-31', '更早'),
      ]) {
        final time = ThreadListTime.of(
          thread(last: raw),
          ThreadSort.latest,
          now: now,
        );
        expect(time.label, label);
        expect(time.section, section);
      }
    },
  );

  test('yesterday crosses years and midnight using calendar dates', () {
    final jan1 = DateTime(2027, 1, 1, 0, 3);
    for (final raw in ['2026-12-31 23:59', '昨天 23:59', '4 分钟前']) {
      final time = ThreadListTime.of(
        thread(last: raw),
        ThreadSort.latest,
        now: jan1,
      );
      expect(time.label, '昨天 23:59');
      expect(time.section, '昨天');
    }
  });

  test('recognised relative source times retain the correct day', () {
    final midnight = DateTime(2026, 11, 4, 0, 10);
    for (final (raw, label, section) in [
      ('刚刚', '00:10', '今天'),
      ('今天 0:09', '00:09', '今天'),
      ('30分钟前', '昨天 23:40', '昨天'),
      ('2 小时前', '昨天 22:10', '昨天'),
      ('前天 12:30', '11-2', '更早'),
    ]) {
      final time = ThreadListTime.of(
        thread(last: raw),
        ThreadSort.latest,
        now: midnight,
      );
      expect(time.label, label);
      expect(time.section, section);
    }
  });

  test('unknown reply times never become creation times or date groups', () {
    for (final raw in [
      null,
      '',
      ' ',
      '源站时间未知',
      '2026-2-30 09:00',
      '2026-11-4 25:00',
      '999999999999999999999分钟前',
    ]) {
      final time = ThreadListTime.of(
        thread(createdAt: now, last: raw),
        ThreadSort.latest,
        now: now,
      );
      expect(time.at, isNull);
      expect(time.section, isNull);
      expect(time.label, raw == null || raw.trim().isEmpty ? null : raw);
    }
  });

  test('missing creation time is not replaced with the last reply', () {
    final time = ThreadListTime.of(
      thread(last: '2026-11-4 09:00'),
      ThreadSort.posted,
      now: now,
    );
    expect(time.at, isNull);
    expect(time.label, isNull);
    expect(time.section, isNull);
  });

  test('a date without a time never invents midnight in its label', () {
    final time = ThreadListTime.of(
      thread(last: '2026-11-4'),
      ThreadSort.latest,
      now: now,
    );
    expect(time.label, '11-4');
    expect(time.section, '今天');
  });

  test('future server dates are not labelled as earlier', () {
    final time = ThreadListTime.of(
      thread(last: '2026-11-5 09:00'),
      ThreadSort.latest,
      now: now,
    );
    expect(time.label, '11-5');
    expect(time.section, isNull);
  });
}
