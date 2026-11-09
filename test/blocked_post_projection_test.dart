import 'package:chh_app/data/blocked_post_projection.dart';
import 'package:chh_app/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'known blocked quotes and feedback disappear without changing server totals',
    () {
      const target = Post(
        pid: 2,
        floor: 2,
        author: '作者',
        authorUid: '20',
        timeRaw: '',
        content: [TextBlock('不可展示的原文')],
      );
      const raw = Post(
        pid: 3,
        floor: 3,
        author: '其他人',
        authorUid: '30',
        timeRaw: '',
        content: [
          QuoteBlock(
            [TextBlock('不可展示的原文')],
            reference: PostReference(
              tid: 1,
              pid: 2,
              url: 'https://www.chiphell.com/',
            ),
          ),
          TextBlock('其他人的正文'),
        ],
        comments: [
          PostComment(author: '作者', uid: '20', text: '隐藏点评'),
          PostComment(author: '其他人', uid: '30', text: '正常点评'),
        ],
        rating: PostRating(
          summary: ['参与人数 2', '邪恶指数 +10'],
          entries: [
            RatingEntry(user: '作者', uid: '20', score: '+5'),
            RatingEntry(user: '其他人', uid: '30', score: '+5'),
          ],
        ),
      );
      final shown = projectBlockedPost(
        raw,
        tid: 1,
        knownPosts: {2: target},
        isBlocked: (uid) => uid == '20',
      );
      expect(
        shown.content.first,
        isA<QuoteBlock>()
            .having(
              (b) => (b.children.single as TextBlock).text,
              'text',
              '引用已屏蔽楼层',
            )
            .having((b) => b.source, 'source', isNull)
            .having((b) => b.reference, 'reference', isNull),
      );
      expect(shown.comments.single.text, '正常点评');
      expect(shown.rating!.entries.single.uid, '30');
      expect(shown.rating!.participants, 2);
      expect(shown.rating!.summary, raw.rating!.summary);
      expect(raw.content.first, isA<QuoteBlock>());
      expect(raw.comments.length, 2);
    },
  );
}
