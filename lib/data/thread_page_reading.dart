import '../models/models.dart';
import 'thread_conversation_index.dart';
import 'user_block_index.dart';

// Owned by the parsed detail's lifetime, including repository cache hits.
final parsedThreadReading = Expando<ThreadPageReading>();

/// Account-independent reading data for one parsed source page.
class ThreadPageReading {
  ThreadPageReading(ThreadDetail detail)
    : index = ThreadConversationIndex.build(
        tid: detail.tid,
        posts: detail.posts,
        sourceComplete: detail.page.current == 1 && !detail.page.hasNext,
      ) {
    for (final post in index.postsByPid.values) {
      final opening = postIsOpening(post);
      if (opening) {
        _opening ??= post;
      } else {
        _replyCount++;
      }
      if (post.floor > _maxFloor) _maxFloor = post.floor;
      _allFloorsKnown &= post.floorIsKnown;
      final uid = UserBlockIndex.normalizeUid(post.authorUid);
      if (uid != null) {
        _repliesByAuthor.update(
          uid,
          (count) => count + (opening ? 0 : 1),
          ifAbsent: () => opening ? 0 : 1,
        );
      }
    }
    rootPids = Set.unmodifiable(index.roots.map((post) => post.pid));
  }

  final ThreadConversationIndex index;
  late final Set<int> rootPids;
  final _repliesByAuthor = <String, int>{};
  Post? _opening;
  int _replyCount = 0;
  int _maxFloor = 0;
  bool _allFloorsKnown = true;

  Post? get opening => _opening;
  int? get floorTotal => _allFloorsKnown ? _maxFloor : null;

  ({int shown, bool complete}) visibleCounts(Iterable<String> blockedUids) {
    var shown = _replyCount;
    var complete = index.sourceComplete;
    for (final uid in blockedUids) {
      final count = _repliesByAuthor[uid];
      if (count == null) continue;
      shown -= count;
      complete = false;
    }
    return (shown: shown, complete: complete);
  }
}
