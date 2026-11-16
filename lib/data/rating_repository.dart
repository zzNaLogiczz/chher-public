import '../core/app_log.dart';
import '../core/chh_urls.dart';
import '../models/models.dart';
import '../network/chh_client.dart';
import '../parser/rating_parser.dart';

class RatingDetails {
  final List<RatingEntry> entries;
  const RatingDetails(this.entries);

  String? reasonFor(RatingEntry entry) {
    final value = ratingScoreValue(entry.score);
    if (value == null) return null;
    final matches = entries
        .where(
          (item) =>
              item.user == entry.user && ratingScoreValue(item.score) == value,
        )
        .toList();
    if (matches.length != 1) return null;
    return matches.single.reason;
  }
}

/// A floor is read only on demand, once per account session, including failures.
class RatingRepository {
  final ChhClient client;
  final int Function()? sessionRevision;
  final _cache = <(int, int), RatingDetails?>{};
  final _inFlight = <(int, int), Future<RatingDetails?>>{};
  final _diagnosedThreads = <int>{};
  int? _revision;

  RatingRepository(this.client, {this.sessionRevision});

  (int, int)? _key(PostRating rating) {
    final revision = sessionRevision?.call();
    if (_revision != revision) {
      _revision = revision;
      _cache.clear();
      _inFlight.clear();
      _diagnosedThreads.clear();
    }
    final tid = rating.tid, pid = rating.pid;
    return tid == null || pid == null || tid <= 0 || pid <= 0
        ? null
        : (tid, pid);
  }

  RatingDetails? cached(PostRating rating) => _cache[_key(rating)];
  bool hasAttempted(PostRating rating) {
    final key = _key(rating);
    return _cache.containsKey(key) || _inFlight.containsKey(key);
  }

  bool isLoading(PostRating rating) => _inFlight.containsKey(_key(rating));

  Uri? detailsUrl(PostRating rating) {
    final tid = rating.tid, pid = rating.pid;
    if (tid == null || pid == null || tid <= 0 || pid <= 0) return null;
    final observed = rating.detailsUrl;
    return observed != null &&
            ChhUrls.isViewRatings(observed, tid: tid, pid: pid)
        ? observed
        : ChhUrls.viewRatings(tid, pid);
  }

  Future<RatingDetails?> load(PostRating rating) {
    final key = _key(rating);
    if (key == null) return Future.value(null);
    if (_cache.containsKey(key)) return Future.value(_cache[key]);
    final revision = _revision;
    return _inFlight[key] ??= _load(rating, key, revision).whenComplete(() {
      if (_revision == revision) _inFlight.remove(key);
    });
  }

  Future<RatingDetails?> _load(
    PostRating rating,
    (int, int) key,
    int? revision,
  ) async {
    RatingDetails? result;
    try {
      final html = await client.getHtml(detailsUrl(rating)!);
      if (sessionRevision?.call() != revision) return null;
      final entries = [...parseRatingDetails(html)];
      RatingContentPage? content;
      RatingEntry? unresolved;
      for (final target in rating.entries) {
        if (!isRatingReasonTruncated(target.reason)) continue;
        content ??= RatingContentPage(html);
        // A second matching row may lack the standard template's UID/date.
        // Do not let that omitted row make the standard result look unique.
        if (content.hasAmbiguousMatch(target)) {
          entries.removeWhere(
            (item) =>
                item.user == target.user &&
                ratingScoreValue(item.score) == ratingScoreValue(target.score),
          );
          unresolved ??= target;
          continue;
        }
        if (RatingDetails(entries).reasonFor(target) != null) continue;
        final reason = content.reasonFor(target);
        if (reason == null) {
          unresolved ??= target;
          continue;
        }
        entries.removeWhere(
          (item) =>
              item.user == target.user &&
              ratingScoreValue(item.score) == ratingScoreValue(target.score),
        );
        entries.add(
          RatingEntry(
            user: target.user,
            score: target.score,
            uid: target.uid,
            reason: reason,
            credit: target.credit,
          ),
        );
      }
      if (unresolved != null && !_diagnosedThreads.contains(key.$1)) {
        final messages = content!.diagnostics(unresolved);
        if (messages.isNotEmpty) {
          _diagnosedThreads.add(key.$1);
          for (final message in messages) {
            AppLog.w('RATING', message);
          }
        }
      }
      if (entries.isNotEmpty) {
        result = RatingDetails(List.unmodifiable(entries));
      }
    } catch (_) {
      // Keep the original text and web link; a failed floor stays in cooldown.
    }
    if (sessionRevision?.call() != revision) return null;
    _cache[key] = result;
    return result;
  }
}
