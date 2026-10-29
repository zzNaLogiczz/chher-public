/// Groups loaded portal comments into one-level conversations.
///
/// Portal quotes carry no cid. The site's requote BBCode is
/// `[quote]author: message[/quote]`, with the quoted comment's own quotes
/// stripped and its message possibly truncated. A reply is attached only when
/// exactly one earlier loaded comment by that author starts with the quoted
/// text; anything ambiguous or missing stays a top-level comment with its quote.
library;

import '../models/article_discussion.dart';
import '../models/models.dart';

class ArticleCommentIndex {
  /// Top-level comments in source order.
  final List<ArticleComment> roots;
  final Map<int, List<ArticleComment>> _replies;
  final Map<int, ArticleComment> _targets;
  final Map<int, int> _rootOf;

  const ArticleCommentIndex._(
    this.roots,
    this._replies,
    this._targets,
    this._rootOf,
  );

  static const empty = ArticleCommentIndex._([], {}, {}, {});

  /// [pinnedRoots] are comments already shown as top-level. They stay there
  /// when a later page reveals what they quoted, so read comments never move.
  factory ArticleCommentIndex.build(
    List<ArticleComment> items, {
    Set<int> pinnedRoots = const {},
  }) {
    final targets = <int, ArticleComment>{};
    for (final comment in items) {
      final target = _resolveTarget(comment, items);
      if (target != null) targets[comment.cid] = target;
    }
    final rootOf = <int, int>{};
    int rootFor(ArticleComment comment) {
      var current = comment;
      // Targets are strictly older (smaller cid), so this walk always ends.
      while (!pinnedRoots.contains(current.cid)) {
        final parent = targets[current.cid];
        if (parent == null) break;
        current = parent;
      }
      return current.cid;
    }

    final roots = <ArticleComment>[];
    final replies = <int, List<ArticleComment>>{};
    for (final comment in items) {
      final root = rootFor(comment);
      rootOf[comment.cid] = root;
      if (root == comment.cid) {
        roots.add(comment);
      } else {
        (replies[root] ??= []).add(comment);
      }
    }
    // Replies read as a conversation: oldest first, regardless of page order.
    for (final list in replies.values) {
      list.sort((a, b) => a.cid.compareTo(b.cid));
    }
    return ArticleCommentIndex._(roots, replies, targets, rootOf);
  }

  List<ArticleComment> repliesFor(int rootCid) => _replies[rootCid] ?? const [];

  /// The comment this one quoted, when it could be identified.
  ArticleComment? targetOf(int cid) => _targets[cid];

  bool isGroupedReply(int cid) => _rootOf[cid] != null && _rootOf[cid] != cid;

  /// Name to show for a deep reply; direct replies to the root show none.
  String? replyToAuthor(int cid) {
    final target = _targets[cid];
    if (target == null || !isGroupedReply(cid) || target.cid == _rootOf[cid]) {
      return null;
    }
    final name = target.author.trim();
    return name.isEmpty ? null : name;
  }

  static ArticleComment? _resolveTarget(
    ArticleComment comment,
    List<ArticleComment> items,
  ) {
    final quote = comment.content.whereType<QuoteBlock>().firstOrNull;
    if (quote == null) return null;
    final quoted = _plain(quote.children);
    final colon = quoted.indexOf(':');
    if (colon <= 0) return null;
    final author = quoted.substring(0, colon).trim();
    var text = _squash(quoted.substring(colon + 1));
    // The site may cut long messages; only the kept prefix can be compared.
    if (text.endsWith('...')) text = text.substring(0, text.length - 3);
    if (author.isEmpty || text.isEmpty) return null;
    ArticleComment? match;
    for (final candidate in items) {
      if (candidate.cid >= comment.cid || candidate.author.trim() != author) {
        continue;
      }
      if (!_squash(bodyText(candidate)).startsWith(text)) continue;
      if (match != null) return null;
      match = candidate;
    }
    return match;
  }

  /// Comment text without its own quotes, as the site strips them on requote.
  static String bodyText(ArticleComment comment) {
    if (comment.content.isEmpty) return comment.text;
    return _plain(
      comment.content.where((block) => block is! QuoteBlock).toList(),
    );
  }

  static String _plain(List<ContentBlock> blocks) => blocks
      .map(
        (block) => switch (block) {
          TextBlock(:final text) => text,
          QuoteBlock(:final children) => _plain(children),
          _ => '',
        },
      )
      .join(' ');

  static String _squash(String text) => text.replaceAll(RegExp(r'\s+'), '');
}
