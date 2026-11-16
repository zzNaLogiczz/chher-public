import 'package:chh_app/design/theme.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/models/poll.dart';
import 'package:chh_app/pages/thread_detail_page.dart';
import 'package:chh_app/parser/thread_parser.dart';
import 'package:chh_app/widgets/connected_thread_poll.dart';
import 'package:chh_app/widgets/post_card.dart';
import 'package:chh_app/widgets/post_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'thread_attachment_parser_test.dart' show attachment, attachmentImage;

const _poll = ThreadPoll(
  tid: 42,
  multiple: false,
  maxChoices: 1,
  alreadyVoted: true,
  options: [PollOption(text: '本地选项', votes: 3, percentage: 100)],
);

const _opening = Post(
  pid: 1,
  floor: 1,
  author: '本地作者',
  timeRaw: '',
  content: [TextBlock('本地正文')],
  rating: PostRating(
    summary: ['参与人数 1', '邪恶指数 +1'],
    entries: [RatingEntry(user: '本地评分者', score: '+1', reason: '评分附言')],
  ),
  comments: [PostComment(author: '本地点评者', text: '点评内容')],
);

Future<void> _mount(WidgetTester tester, Widget body) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(theme: buildAppTheme(Brightness.light), home: body),
  );
  await tester.pumpAndSettle();
}

void main() {
  test(
    'poll stays outside body and preserves inline and external attachments',
    () {
      final html = '''
<table id="pid1"><tr><td>
<div class="authi"><strong><a href="space-uid-1.html">本地作者</a></strong></div>
<a id="postnum1">1#</a><div class="pct"><div class="pcb"><div class="t_fsz"><div class="pcbs">
<table><tr><td id="postmessage_1">本地正文
<img id="aimg_700" src="https://example.invalid/inline.jpg"></td></tr></table>
<form id="poll" action="forum.php?mod=misc&amp;action=votepoll&amp;tid=42">
<div class="pinf"><strong>单选投票</strong>共有 3 人参与投票</div>
<table><tr><td class="pvt"><label>1. 本地选项</label></td></tr></table>
</form></div>${attachment(attachmentImage('701'))}</div></div></div></td></tr></table>''';
      final detail = parseThread(html, tid: 42);
      expect(detail.poll?.options.single.text, '本地选项');
      final content = detail.posts.single.content;
      expect(content.whereType<TextBlock>().map((b) => b.text).join(), '本地正文');
      expect(content.whereType<ImageBlock>().map((b) => b.url), [
        'https://example.invalid/inline.jpg',
        'https://example.invalid/701.jpg',
      ]);
      expect(parseThread(html, tid: 42, fallbackPage: 2).poll, isNull);
    },
  );

  for (final lazy in [false, true]) {
    testWidgets('poll slot precedes opening ratings and comments, lazy=$lazy', (
      tester,
    ) async {
      const pollMarker = SizedBox(key: ValueKey('poll-slot'), height: 80);
      await _mount(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: lazy
                ? const Column(
                    children: [
                      PostCard.header(post: _opening, isOpening: true),
                      PostCard.block(
                        post: _opening,
                        isOpening: true,
                        contentBlock: TextBlock('本地正文'),
                      ),
                      PostCard.footer(
                        post: _opening,
                        isOpening: true,
                        pollCard: pollMarker,
                      ),
                    ],
                  )
                : const PostCard(
                    post: _opening,
                    isOpening: true,
                    pollCard: pollMarker,
                  ),
          ),
        ),
      );
      final body = find.text('本地正文');
      final poll = find.byKey(const ValueKey('poll-slot'));
      final feedback = find.byType(OpeningFeedback);
      expect(body, findsOneWidget);
      expect(poll, findsOneWidget);
      expect(feedback, findsOneWidget);
      expect(
        tester.getBottomLeft(body).dy,
        lessThanOrEqualTo(tester.getTopLeft(poll).dy),
      );
      expect(
        tester.getBottomLeft(poll).dy,
        lessThanOrEqualTo(tester.getTopLeft(feedback).dy),
      );
      expect(
        tester.widget<OpeningFeedback>(feedback).rating,
        same(_opening.rating),
      );
      expect(
        tester.widget<OpeningFeedback>(feedback).comments,
        same(_opening.comments),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'thread attaches one poll to opening footer while preloading later page',
    (tester) async {
      final reads = <int>[];
      await _mount(
        tester,
        ThreadDetailPage(
          tid: 42,
          title: '本地投票帖',
          preloadPages: 2,
          loadPage: (page, _, _) async {
            reads.add(page);
            return ThreadDetail(
              tid: 42,
              title: '本地投票帖',
              // Even a source that repeats poll markup on page 2 must not duplicate the card.
              poll: _poll,
              posts: page == 1
                  ? [_opening]
                  : const [
                      Post(
                        pid: 2,
                        floor: 2,
                        author: '本地回复者',
                        timeRaw: '',
                        content: [TextBlock('本地回复')],
                      ),
                    ],
              page: PageInfo(current: page, hasNext: page == 1),
            );
          },
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(reads, containsAll([1, 2]));
      expect(find.byType(ConnectedThreadPoll), findsOneWidget);
      final openingFooters = tester
          .widgetList<PostCard>(find.byType(PostCard))
          .where((w) => w.pollCard != null)
          .toList();
      expect(openingFooters, hasLength(1));
      expect(openingFooters.single.post.pid, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'confirmed poll survives lazy footer disposal without moving the reader',
    (tester) async {
      await _mount(
        tester,
        ThreadDetailPage(
          tid: 42,
          title: '本地长帖',
          preloadPages: 1,
          loadPage: (page, _, _) async => ThreadDetail(
            tid: 42,
            title: '本地长帖',
            poll: _poll,
            posts: [
              _opening,
              for (var floor = 2; floor <= 40; floor++)
                Post(
                  pid: floor,
                  floor: floor,
                  author: '本地回复者$floor',
                  timeRaw: '',
                  content: [TextBlock(List.filled(5, '本地回复$floor').join('\n'))],
                ),
            ],
            page: const PageInfo(current: 1, hasNext: false),
          ),
        ),
      );
      final card = tester.widget<ConnectedThreadPoll>(
        find.byType(ConnectedThreadPoll),
      );
      const confirmed = ThreadPoll(
        tid: 42,
        multiple: false,
        maxChoices: 1,
        alreadyVoted: true,
        options: [
          PollOption(text: '本地选项', votes: 4, percentage: 100, mine: true),
        ],
      );
      final scrollable = find.byType(Scrollable).first;
      final position = tester.state<ScrollableState>(scrollable).position;
      final offset = position.pixels;
      // Deliver a locally confirmed result through the same boundary as fake transport.
      card.onUpdated!(confirmed);
      await tester.pump();
      expect(position.pixels, offset);
      await tester.drag(scrollable, const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(find.byType(ConnectedThreadPoll), findsNothing);
      await tester.drag(scrollable, const Offset(0, 4000));
      await tester.pumpAndSettle();
      final rebuilt = tester.widget<ConnectedThreadPoll>(
        find.byType(ConnectedThreadPoll),
      );
      expect(rebuilt.poll, same(confirmed));
      expect(rebuilt.poll.options.single.mine, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'landing on a later page never treats its first reply as a poll opening',
    (tester) async {
      await _mount(
        tester,
        ThreadDetailPage(
          tid: 42,
          title: '本地后续页',
          initialPage: 2,
          preloadPages: 1,
          loadPage: (page, _, _) async => ThreadDetail(
            tid: 42,
            title: '本地后续页',
            poll: _poll,
            posts: const [
              Post(
                pid: 22,
                floor: 22,
                author: '后续回复者',
                timeRaw: '',
                content: [TextBlock('后续页正文')],
              ),
            ],
            page: PageInfo(current: page, hasNext: false),
          ),
        ),
      );
      expect(find.byType(ConnectedThreadPoll), findsNothing);
      expect(find.text('后续页正文'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
