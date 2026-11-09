/// Display-only filtering. Original pages and reply relationships stay intact.
library;

import '../models/models.dart';

Post projectBlockedPost(
  Post post, {
  required int tid,
  required Map<int, Post> knownPosts,
  required bool Function(String?) isBlocked,
}) {
  List<ContentBlock> project(List<ContentBlock> blocks) => [
    for (final block in blocks)
      if (block is QuoteBlock && !block.isNotice)
        if (block.reference?.tid == tid &&
            isBlocked(knownPosts[block.reference?.pid]?.authorUid))
          const QuoteBlock([TextBlock('引用已屏蔽楼层')])
        else
          QuoteBlock(
            project(block.children),
            source: block.source,
            reference: block.reference,
            unlinkedEvidence: block.unlinkedEvidence,
          )
      else
        block,
  ];
  final rating = post.rating;
  return post.copyWith(
    content: project(post.content),
    comments: post.comments.where((c) => !isBlocked(c.uid)).toList(),
    rating: rating == null
        ? null
        : PostRating(
            // Server totals describe all participants, including hidden authors.
            summary: rating.summary,
            entries: rating.entries.where((e) => !isBlocked(e.uid)).toList(),
          ),
  );
}
