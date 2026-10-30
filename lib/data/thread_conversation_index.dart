/// Conservative two-level projection of the currently loaded forum posts.
library;

import '../models/models.dart';

/// A page-local fallback ordinal must never identify a thread's opening post.
bool postIsOpening(Post post) => post.floorIsKnown && post.floor == 1;

enum ThreadConversationStatus {
  opening,
  independent,
  reply,
  replyToOpening,
  multipleReferences,
  unknownReference,
  crossThread,
  selfReference,
  missingTarget,
  notEarlier,
  cycle,
}

class ThreadConversationResolution {
  final ThreadConversationStatus status;
  final int rootPid;
  final PostReference? directTarget;
  final bool isPinnedRoot;

  const ThreadConversationResolution({
    required this.status,
    required this.rootPid,
    this.directTarget,
    this.isPinnedRoot = false,
  });

  bool get isGroupedReply =>
      status == ThreadConversationStatus.reply && !isPinnedRoot;
}

/// This is a snapshot, not a persistent or account-wide conversation cache.
///
/// Collections retain first-occurrence input order. Duplicate PIDs keep their
/// first Post object. [roots] includes the known opening post; consumers may
/// partition it with [postIsOpening]. All counts describe loaded objects only.
/// A quotation is evidence for presentation, never an authenticated reply edge.
class ThreadConversationIndex {
  final int tid;
  final bool sourceComplete;
  final Map<int, Post> postsByPid;
  final List<Post> roots;
  final Map<int, List<Post>> _replies;
  final Map<int, ThreadConversationResolution> _resolutions;
  final int loadedReplyCount;

  const ThreadConversationIndex._({
    required this.tid,
    required this.sourceComplete,
    required this.postsByPid,
    required this.roots,
    required this._replies,
    required this._resolutions,
    required this.loadedReplyCount,
  });

  int get loadedPostCount => postsByPid.length;

  /// Only descendants grouped under this root, flattened into a single level.
  List<Post> repliesFor(int rootPid) => _replies[rootPid] ?? const <Post>[];

  /// Null means this PID is absent from this snapshot.
  int? rootPidFor(int pid) => _resolutions[pid]?.rootPid;

  /// A single top-level reference is retained even when unsafe to group.
  /// Multiple or unresolvable top-level quotations have no unique target.
  PostReference? directTargetFor(int pid) => _resolutions[pid]?.directTarget;

  ThreadConversationResolution? resolutionFor(int pid) => _resolutions[pid];
  ThreadConversationStatus? statusFor(int pid) => _resolutions[pid]?.status;

  factory ThreadConversationIndex.build({
    required int tid,
    required Iterable<Post> posts,
    bool sourceComplete = false,
    Set<int> pinnedRootPids = const <int>{},
  }) {
    final byPid = <int, Post>{};
    for (final post in posts) {
      byPid.putIfAbsent(post.pid, () => post);
    }
    final order = <int, int>{};
    var ordinal = 0;
    for (final pid in byPid.keys) {
      order[pid] = ordinal++;
    }

    final parents = <int, int>{};
    final targets = <int, PostReference>{};
    final statuses = <int, ThreadConversationStatus>{};
    final rootByPid = <int, int>{};

    for (final post in byPid.values) {
      QuoteBlock? quotation;
      var quoteCount = 0;
      // Nested quotations are historical context, not another direct reply.
      for (final block in post.content) {
        if (block is! QuoteBlock || block.isNotice) continue;
        quoteCount++;
        quotation = block;
        if (quoteCount > 1) break;
      }
      final reference = quoteCount == 1 ? quotation?.reference : null;
      if (reference != null) targets[post.pid] = reference;

      ThreadConversationStatus? status;
      if (postIsOpening(post)) {
        status = ThreadConversationStatus.opening;
      } else if (quoteCount == 0) {
        status = ThreadConversationStatus.independent;
      } else if (quoteCount > 1) {
        status = ThreadConversationStatus.multipleReferences;
      } else if (reference == null) {
        status = ThreadConversationStatus.unknownReference;
      } else if (reference.tid != tid) {
        status = ThreadConversationStatus.crossThread;
      } else if (reference.pid == post.pid) {
        status = ThreadConversationStatus.selfReference;
      } else {
        final target = byPid[reference.pid];
        if (target == null) {
          status = ThreadConversationStatus.missingTarget;
        } else {
          final earlier = post.floorIsKnown && target.floorIsKnown
              ? target.floor < post.floor
              : order[target.pid]! < order[post.pid]!;
          if (!earlier) {
            status = ThreadConversationStatus.notEarlier;
          } else if (postIsOpening(target)) {
            // Directly addressing the opening post remains a top-level comment.
            status = ThreadConversationStatus.replyToOpening;
          } else {
            parents[post.pid] = target.pid;
          }
        }
      }
      if (status != null) {
        statuses[post.pid] = status;
        rootByPid[post.pid] = post.pid;
      }
    }

    // A caller may freeze an already presented root as a view boundary while
    // loading more pages. Its quotation remains the same; no semantic edge is
    // invented or discarded, and unseen pins never create synthetic posts.
    for (final pid in byPid.keys) {
      if (!pinnedRootPids.contains(pid)) continue;
      rootByPid[pid] = pid;
      statuses.putIfAbsent(pid, () => ThreadConversationStatus.reply);
    }

    // Each unresolved PID enters a path once. Resolved paths are compressed;
    // no recursive stack or repeated ancestor traversal is needed for long chains.
    for (final pid in byPid.keys) {
      if (rootByPid.containsKey(pid)) continue;
      final path = <int>[];
      final inPath = <int>{};
      var current = pid;
      while (!rootByPid.containsKey(current) && inPath.add(current)) {
        path.add(current);
        current = parents[current]!;
      }
      if (rootByPid.containsKey(current) &&
          statuses[current] != ThreadConversationStatus.cycle) {
        final root = rootByPid[current]!;
        for (final member in path) {
          rootByPid[member] = root;
          statuses[member] = ThreadConversationStatus.reply;
        }
      } else {
        // Mixed known/unknown ordinals can form a cycle despite edge checks.
        // Keep the cycle and every incoming chain independent, with context intact.
        for (final member in path) {
          rootByPid[member] = member;
          statuses[member] = ThreadConversationStatus.cycle;
        }
      }
    }

    final roots = <Post>[];
    final replies = <int, List<Post>>{};
    final resolutions = <int, ThreadConversationResolution>{};
    var loadedReplies = 0;
    for (final post in byPid.values) {
      final root = rootByPid[post.pid]!;
      resolutions[post.pid] = ThreadConversationResolution(
        status: statuses[post.pid]!,
        rootPid: root,
        directTarget: targets[post.pid],
        isPinnedRoot: pinnedRootPids.contains(post.pid),
      );
      if (root == post.pid) {
        roots.add(post);
      } else {
        (replies[root] ??= []).add(post);
        loadedReplies++;
      }
    }

    return ThreadConversationIndex._(
      tid: tid,
      sourceComplete: sourceComplete,
      postsByPid: Map.unmodifiable(byPid),
      roots: List.unmodifiable(roots),
      replies: Map.unmodifiable({
        for (final entry in replies.entries)
          entry.key: List<Post>.unmodifiable(entry.value),
      }),
      resolutions: Map.unmodifiable(resolutions),
      loadedReplyCount: loadedReplies,
    );
  }
}
