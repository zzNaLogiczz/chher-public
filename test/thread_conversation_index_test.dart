import 'package:chh_app/data/thread_conversation_index.dart';
import 'package:chh_app/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

const _tid = 42;
PostReference _reference(int pid, {int tid = _tid}) => PostReference(
  tid: tid,
  pid: pid,
  url:
      'https://www.chiphell.com/forum.php?mod=redirect&goto=findpost&ptid=$tid&pid=$pid',
);
QuoteBlock _quote(int pid, {int tid = _tid, List<ContentBlock>? children}) =>
    QuoteBlock(
      children ?? const [TextBlock('保留原引文')],
      source: '原作者的引用说明',
      reference: _reference(pid, tid: tid),
    );
Post _post(
  int pid,
  int floor, {
  int? target,
  bool known = true,
  String? authorUid,
  List<ContentBlock>? content,
}) => Post(
  pid: pid,
  floor: floor,
  floorIsKnown: known,
  author: '用户$pid',
  authorUid: authorUid,
  timeRaw: '',
  content: content ?? [if (target != null) _quote(target), TextBlock('正文$pid')],
);
List<int> _pids(Iterable<Post> posts) => posts.map((post) => post.pid).toList();
ThreadConversationIndex _build(Iterable<Post> posts, {bool complete = false}) =>
    ThreadConversationIndex.build(
      tid: _tid,
      posts: posts,
      sourceComplete: complete,
    );

void main() {
  test('only a known first floor is the opening post', () {
    expect(postIsOpening(_post(1, 1)), isTrue);
    expect(postIsOpening(_post(2, 1, known: false)), isFalse);
    expect(postIsOpening(_post(3, 2)), isFalse);
  });

  test(
    'opening references stay top-level and deeper chains flatten under their first comment',
    () {
      final opening = _post(1, 1);
      final comment = _post(2, 2, target: 1);
      final direct = _post(3, 3, target: 2);
      final deeper = _post(4, 4, target: 3);
      final index = _build([opening, comment, direct, deeper, _post(5, 5)]);
      expect(_pids(index.roots), [1, 2, 5]);
      expect(_pids(index.repliesFor(2)), [3, 4]);
      expect(index.repliesFor(1), isEmpty);
      expect(index.rootPidFor(4), 2);
      expect(index.directTargetFor(4)?.pid, 3);
      expect(index.directTargetFor(2)?.pid, 1);
      expect(index.statusFor(1), ThreadConversationStatus.opening);
      expect(index.statusFor(2), ThreadConversationStatus.replyToOpening);
      expect(index.resolutionFor(4)?.isGroupedReply, isTrue);
      expect(identical(index.postsByPid[4], deeper), isTrue);
      expect(
        deeper.content.whereType<QuoteBlock>().single.children.single,
        isA<TextBlock>(),
      );
      expect(index.loadedPostCount, 5);
      expect(index.loadedReplyCount, 2);
      expect(index.sourceComplete, isFalse);
    },
  );

  test(
    'nested historical references never supply or multiply the direct target',
    () {
      final unknownOuter = QuoteBlock([_quote(2)]);
      final explicitOuter = _quote(2, children: [_quote(3), _quote(4)]);
      final index = _build([
        _post(2, 2),
        _post(3, 3, content: [unknownOuter, const TextBlock('正文')]),
        _post(4, 4, content: [explicitOuter]),
        _post(5, 5, content: const [TextBlock('回复 #2，仅文字不是引用关系')]),
      ]);
      expect(_pids(index.roots), [2, 3, 5]);
      expect(_pids(index.repliesFor(2)), [4]);
      expect(index.statusFor(3), ThreadConversationStatus.unknownReference);
      expect(index.directTargetFor(3), isNull);
      expect(index.directTargetFor(4)?.pid, 2);
      expect(index.statusFor(5), ThreadConversationStatus.independent);
      expect(
        identical(index.postsByPid[3]!.content.first, unknownOuter),
        isTrue,
      );
    },
  );

  test(
    'multiple top-level quotations stay independent even when their targets match',
    () {
      final quotes = [_quote(2), _quote(2)];
      final index = _build([_post(2, 2), _post(3, 3, content: quotes)]);
      expect(_pids(index.roots), [2, 3]);
      expect(index.statusFor(3), ThreadConversationStatus.multipleReferences);
      expect(index.directTargetFor(3), isNull);
      expect(identical(index.postsByPid[3]!.content, quotes), isTrue);
      expect(index.postsByPid[3]!.content, hasLength(2));
    },
  );

  test(
    'cross-thread, self, and missing targets keep their original references and roots',
    () {
      final external = _quote(2, tid: 99);
      final self = _quote(4);
      final missing = _quote(999);
      final index = _build([
        _post(2, 2),
        _post(3, 3, content: [external]),
        _post(4, 4, content: [self]),
        _post(5, 5, content: [missing]),
      ], complete: true);
      expect(_pids(index.roots), [2, 3, 4, 5]);
      expect(index.statusFor(3), ThreadConversationStatus.crossThread);
      expect(index.statusFor(4), ThreadConversationStatus.selfReference);
      expect(index.statusFor(5), ThreadConversationStatus.missingTarget);
      expect(identical(index.directTargetFor(3), external.reference), isTrue);
      expect(identical(index.directTargetFor(4), self.reference), isTrue);
      expect(identical(index.directTargetFor(5), missing.reference), isTrue);
      expect(index.sourceComplete, isTrue);
      expect(index.loadedPostCount, 4);
    },
  );

  test(
    'known floors reject later and equal targets regardless of their input positions',
    () {
      final index = _build([
        _post(2, 5),
        _post(3, 3, target: 2),
        _post(4, 5, target: 2),
      ]);
      expect(_pids(index.roots), [2, 3, 4]);
      expect(index.statusFor(3), ThreadConversationStatus.notEarlier);
      expect(index.statusFor(4), ThreadConversationStatus.notEarlier);
      expect(index.directTargetFor(3)?.pid, 2);
    },
  );

  test(
    'unknown floors use input order and never become a synthetic opening post',
    () {
      final index = _build([
        _post(3, 1, target: 2, known: false),
        _post(2, 8),
        _post(4, 1, target: 2, known: false),
      ]);
      expect(_pids(index.roots), [3, 2]);
      expect(index.statusFor(3), ThreadConversationStatus.notEarlier);
      expect(index.rootPidFor(4), 2);
      expect(_pids(index.repliesFor(2)), [4]);
      expect(postIsOpening(index.postsByPid[3]!), isFalse);
    },
  );

  test(
    'shuffled known floors resolve safely while root and reply order stays stable',
    () {
      final index = _build([
        _post(5, 5, target: 2),
        _post(2, 2),
        _post(4, 4, target: 2),
        _post(1, 1),
      ]);
      expect(_pids(index.roots), [2, 1]);
      expect(_pids(index.repliesFor(2)), [5, 4]);
      expect(index.rootPidFor(5), 2);
      expect(index.directTargetFor(5)?.pid, 2);
    },
  );

  test(
    'a later loaded page can resolve missing context without mutating an earlier snapshot',
    () {
      final opening = _post(1, 1);
      final reply = _post(3, 3, target: 2);
      final first = _build([opening, reply]);
      expect(first.statusFor(3), ThreadConversationStatus.missingTarget);
      final combined = _build([opening, reply, _post(2, 2)], complete: true);
      expect(combined.rootPidFor(3), 2);
      expect(_pids(combined.roots), [1, 2]);
      expect(_pids(combined.repliesFor(2)), [3]);
      expect(first.rootPidFor(3), 3);
      expect(first.postsByPid.containsKey(2), isFalse);
      expect(
        _build([opening, reply]).statusFor(3),
        ThreadConversationStatus.missingTarget,
      );
    },
  );

  test(
    'a pinned missing-context root stays visible after backfill and receives later replies',
    () {
      final initiallyVisible = _post(3, 3, target: 2);
      final first = _build([initiallyVisible]);
      final pins = first.roots.map((post) => post.pid).toSet();
      final filled = ThreadConversationIndex.build(
        tid: _tid,
        posts: [initiallyVisible, _post(2, 2)],
        pinnedRootPids: pins,
      );
      expect(_pids(filled.roots), [3, 2]);
      expect(filled.rootPidFor(3), 3);
      expect(filled.directTargetFor(3)?.pid, 2);
      expect(filled.resolutionFor(3)?.isPinnedRoot, isTrue);
      expect(filled.resolutionFor(3)?.isGroupedReply, isFalse);
      final appended = ThreadConversationIndex.build(
        tid: _tid,
        posts: [
          initiallyVisible,
          _post(2, 2),
          _post(4, 4, target: 3),
          _post(5, 5, target: 4),
        ],
        pinnedRootPids: pins,
      );
      expect(_pids(appended.roots), [3, 2]);
      expect(_pids(appended.repliesFor(3)), [4, 5]);
      expect(appended.rootPidFor(5), 3);
      expect(appended.directTargetFor(5)?.pid, 4);
      expect(appended.loadedReplyCount, 2);
      // An explicit recomputation without pins restores the ordinary projection.
      final reset = _build(appended.postsByPid.values);
      expect(_pids(reset.roots), [2]);
      expect(_pids(reset.repliesFor(2)), [3, 4, 5]);
      final absentPin = ThreadConversationIndex.build(
        tid: _tid,
        posts: [_post(8, 8)],
        pinnedRootPids: {999},
      );
      expect(absentPin.loadedPostCount, 1);
      expect(absentPin.postsByPid.containsKey(999), isFalse);
    },
  );

  test(
    'the opening author posting again is still a normal comment or reply',
    () {
      final index = _build([
        _post(1, 1, authorUid: 'owner'),
        _post(2, 2, authorUid: 'owner'),
        _post(3, 3, authorUid: 'owner', target: 2),
        _post(4, 4, authorUid: 'owner'),
      ]);
      expect(_pids(index.roots), [1, 2, 4]);
      expect(index.statusFor(2), ThreadConversationStatus.independent);
      expect(index.statusFor(3), ThreadConversationStatus.reply);
      expect(postIsOpening(index.postsByPid[2]!), isFalse);
    },
  );

  test(
    'mixed reliable floors and fallback ordinals cannot merge a cycle or its incoming chain',
    () {
      final index = _build([
        _post(10, 3, target: 30),
        _post(20, 99, target: 10, known: false),
        _post(30, 2, target: 20),
        _post(40, 100, target: 10, known: false),
        _post(50, 4),
        _post(60, 5, target: 50),
      ]);
      expect(_pids(index.roots), [10, 20, 30, 40, 50]);
      for (final pid in [10, 20, 30, 40]) {
        expect(index.statusFor(pid), ThreadConversationStatus.cycle);
        expect(index.rootPidFor(pid), pid);
        expect(index.directTargetFor(pid), isNotNull);
      }
      expect(_pids(index.repliesFor(50)), [60]);
    },
  );

  test(
    'PID dedup keeps first source objects and all projection collections are immutable',
    () {
      final first = _post(2, 2);
      final duplicate = _post(2, 9, target: 999);
      final input = [first, duplicate, _post(4, 4, target: 2), _post(3, 3)];
      final index = _build(input);
      expect(index.postsByPid.keys.toList(), [2, 4, 3]);
      expect(identical(index.postsByPid[2], first), isTrue);
      expect(index.loadedPostCount, 3);
      expect(input, hasLength(4));
      expect(() => index.postsByPid[7] = _post(7, 7), throwsUnsupportedError);
      expect(() => index.roots.add(_post(7, 7)), throwsUnsupportedError);
      expect(() => index.repliesFor(2).clear(), throwsUnsupportedError);
      expect(index.rootPidFor(999), isNull);
      expect(index.resolutionFor(999), isNull);
      expect(index.repliesFor(999), isEmpty);
    },
  );

  test(
    '5000 reversed loaded posts flatten a long chain without recursion or order loss',
    () {
      final posts = [
        for (var pid = 5000; pid >= 1; pid--)
          _post(pid, pid, target: pid == 1 ? null : pid - 1),
      ];
      final index = _build(posts);
      expect(index.loadedPostCount, 5000);
      expect(_pids(index.roots), [2, 1]);
      expect(index.loadedReplyCount, 4998);
      expect(index.repliesFor(2), hasLength(4998));
      expect(index.repliesFor(2).first.pid, 5000);
      expect(index.repliesFor(2).last.pid, 3);
      expect(index.rootPidFor(5000), 2);
      expect(index.directTargetFor(5000)?.pid, 4999);
    },
  );

  test(
    '5000-node mixed-order cycle terminates and preserves every loaded post',
    () {
      final posts = [
        _post(1, 3, target: 5000),
        for (var pid = 2; pid < 5000; pid++)
          _post(pid, pid + 50, target: pid - 1, known: false),
        _post(5000, 2, target: 4999),
      ];
      final index = _build(posts);
      expect(index.loadedPostCount, 5000);
      expect(index.roots, hasLength(5000));
      expect(index.loadedReplyCount, 0);
      expect(index.statusFor(1), ThreadConversationStatus.cycle);
      expect(index.statusFor(5000), ThreadConversationStatus.cycle);
      expect(index.rootPidFor(5000), 5000);
    },
  );
}
