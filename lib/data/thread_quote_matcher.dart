import '../core/chh_urls.dart';
import '../models/models.dart';

String normalizeQuoteText(String text) =>
    text.replaceAll(RegExp(r'[\s\u00a0]+'), ' ').trim();

/// 核对所有日期分量，拒绝 DateTime 自动滚动的非法日期；秒只用于校验。
DateTime? quoteMinute(String raw) {
  final match = RegExp(
    r'^(\d{4})-(\d{1,2})-(\d{1,2}) (\d{1,2}):(\d{2})(?::(\d{2}))?$',
  ).firstMatch(normalizeQuoteText(raw));
  if (match == null) return null;
  final parts = [for (var i = 1; i <= 5; i++) int.parse(match.group(i)!)];
  final second = int.parse(match.group(6) ?? '0');
  final [year, month, day, hour, minute] = parts;
  if (year < 1 || second > 59) return null;
  final date = DateTime.utc(year, month, day, hour, minute);
  if (date.year != year ||
      date.month != month ||
      date.day != day ||
      date.hour != hour ||
      date.minute != minute) {
    return null;
  }
  return date;
}

/// 每次快照重建候选桶，正文按 PID 延迟归一复用，不缓存上次唯一匹配结论。
class ThreadQuoteMatcher {
  final int tid;
  final _candidates = <(String, DateTime), List<Post>>{};
  final _bodies = <int, String>{};

  ThreadQuoteMatcher({required this.tid, required Iterable<Post> posts}) {
    for (final post in posts) {
      if (!post.floorIsKnown || post.lock != null) continue;
      final minute = quoteMinute(post.timeRaw);
      if (minute == null) continue;
      (_candidates[(post.author, minute)] ??= []).add(post);
    }
  }

  PostReference? targetFor(Post post, QuoteBlock quote) {
    final evidence = quote.unlinkedEvidence;
    if (!post.floorIsKnown ||
        quote.isNotice ||
        evidence == null ||
        evidence.tid != tid ||
        quote.children.any((b) => b is QuoteBlock)) {
      return null;
    }
    Post? matched;
    for (final candidate
        in _candidates[(evidence.author, evidence.minute)] ?? const <Post>[]) {
      if (candidate.pid == post.pid || candidate.floor >= post.floor) continue;
      // 只拼接目标自己的文本，排除旧引文、权限提示和附件说明。
      final body = _bodies.putIfAbsent(
        candidate.pid,
        () => normalizeQuoteText(
          candidate.content.whereType<TextBlock>().map((b) => b.text).join(' '),
        ),
      );
      final matches = evidence.truncated
          ? body.startsWith(evidence.excerpt)
          : body == evidence.excerpt;
      if (!matches) continue;
      if (matched != null) return null;
      matched = candidate;
    }
    if (matched == null) return null;
    return PostReference(
      tid: tid,
      pid: matched.pid,
      url:
          '${ChhUrls.base}/forum.php?mod=redirect&goto=findpost&ptid=$tid&pid=${matched.pid}',
    );
  }
}
