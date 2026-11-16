/// Forum-owned interaction specifications; no account limits are invented here.
library;

enum PostActionPermission { unknown, allowed, denied }

enum PostInteractionKind { comment, rating, supplement }

class PostActionCapabilities {
  final PostActionPermission comment;
  final PostActionPermission rating;
  final Uri? commentUrl;
  final Uri? ratingUrl;
  final Uri? supplementUrl;
  const PostActionCapabilities({
    this.comment = PostActionPermission.unknown,
    this.rating = PostActionPermission.unknown,
    this.commentUrl,
    this.ratingUrl,
    this.supplementUrl,
  });
}

class PostCommentForm {
  final int tid;
  final int pid;
  final Uri action;
  final Uri pageUrl;
  final String formhash;
  final Map<String, String> hidden;
  final String sessionIdentity;
  final int? sessionRevision;
  final int maxLength;
  const PostCommentForm({
    required this.tid,
    required this.pid,
    required this.action,
    required this.pageUrl,
    required this.formhash,
    this.hidden = const {},
    this.sessionIdentity = '',
    this.sessionRevision,
    this.maxLength = 200,
  });
}

class RateScoreType {
  final String fieldName;
  final String label;
  final int min;
  final int max;
  final int remaining;
  final List<int> options;
  const RateScoreType({
    required this.fieldName,
    required this.label,
    required this.min,
    required this.max,
    required this.remaining,
    this.options = const [],
  });
  bool get isEvil => label.replaceAll(RegExp(r'\s+'), '').contains('邪恶');
  bool accepts(int score) =>
      score >= min && score <= max && score.abs() <= remaining;
}

class PostRateForm {
  final int tid;
  final int pid;
  final Uri action;
  final Uri pageUrl;
  final String formhash;
  final Map<String, String> hidden;
  final String sessionIdentity;
  final int? sessionRevision;
  final List<RateScoreType> scoreTypes;
  final List<String> reasons;
  const PostRateForm({
    required this.tid,
    required this.pid,
    required this.action,
    required this.pageUrl,
    required this.formhash,
    required this.scoreTypes,
    this.hidden = const {},
    this.sessionIdentity = '',
    this.sessionRevision,
    this.reasons = const [],
  });
  RateScoreType? get evilScoreType =>
      scoreTypes.where((t) => t.isEvil).firstOrNull;
  Map<String, int> get initialScores => {
    for (final t in scoreTypes) t.fieldName: 0,
  };
}

/// A fresh, server-authorized append form for one owned post.
class PostSupplementForm {
  final int tid, pid;
  final Uri action, pageUrl;
  final String formhash, sessionIdentity;
  final int? sessionRevision, maxLength;
  final Map<String, String> hidden;
  const PostSupplementForm({
    required this.tid,
    required this.pid,
    required this.action,
    required this.pageUrl,
    required this.formhash,
    required this.sessionIdentity,
    this.sessionRevision,
    this.maxLength,
    this.hidden = const {},
  });
}
