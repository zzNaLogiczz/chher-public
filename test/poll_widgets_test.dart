import 'dart:async';
import 'package:chh_app/data/poll_repository.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/widgets/poll_voters_sheet.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/models/poll.dart';
import 'package:chh_app/widgets/thread_poll_card.dart';
import 'package:chh_app/ui/press.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ThreadPoll poll({
  bool multi = false,
  bool voted = false,
  bool closed = false,
  bool ended = false,
  bool hidden = false,
  int count = 3,
  bool mine = false,
}) => ThreadPoll(
  tid: 1,
  multiple: multi,
  maxChoices: multi ? 2 : 1,
  participantCount: 331,
  action: Uri.parse(
    'https://www.chiphell.com/forum.php?mod=misc&action=votepoll&tid=1',
  ),
  alreadyVoted: voted,
  closed: closed,
  ended: ended,
  resultsAfterVote: hidden,
  options: List.generate(
    count,
    (i) => PollOption(
      text: '选项 $i',
      id: voted || closed || ended ? null : '$i',
      votes: hidden ? null : i + 1,
      percentage: hidden ? null : 33,
      mine: mine && i == 0,
    ),
  ),
);
Future<void> mount(
  WidgetTester tester,
  ThreadPoll data, {
  AppearanceStyle style = AppearanceStyle.cinnabar,
  Brightness brightness = Brightness.light,
  Future<PollVoteResult> Function(Set<String>)? submit,
  bool reduced = false,
  double width = 360,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(brightness, style),
      home: MediaQuery(
        data: MediaQueryData(
          disableAnimations: reduced,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: width,
              child: ThreadPollCard(poll: data, onSubmit: submit),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder voteButton() =>
    find.byWidgetPredicate((w) => w is PressScale && w.semanticLabel == '投票');

class VotersRepository extends PollRepository {
  final requests = <(String?, int)>[];
  Object? error;
  bool empty = false, rollback = false;
  VotersRepository() : super(ChhClient(fetchers: []));
  @override
  Future<PollVotersPage> participants(
    ThreadPoll poll, {
    String? optionId,
    int page = 1,
  }) async {
    requests.add((optionId, page));
    if (error != null) throw error!;
    return PollVotersPage(
      options: const [
        PollVoterOption(id: 'a', text: '选项甲'),
        PollVoterOption(id: 'b', text: '选项乙'),
      ],
      voters: empty ? [] : [PollVoter(uid: page, name: '本地会员$page')],
      selectedOptionId: optionId ?? 'a',
      page: PageInfo(current: rollback ? 1 : page, hasNext: page < 2),
    );
  }
}

void main() {
  for (final style in AppearanceStyle.values) {
    for (final brightness in Brightness.values) {
      testWidgets('$style $brightness 320dp with 2x type stays readable', (
        tester,
      ) async {
        for (final data in [
          poll(multi: true),
          poll(voted: true),
          poll(closed: true, hidden: true),
        ]) {
          await mount(
            tester,
            data,
            style: style,
            brightness: brightness,
            width: 320,
            textScale: 2,
          );
          expect(tester.takeException(), isNull);
          expect(find.text('331 人参与'), findsOneWidget);
          expect(find.text('选项 0'), findsOneWidget);
        }
      });
      testWidgets('$style $brightness states render and idle tickers stop', (
        tester,
      ) async {
        for (final data in [
          poll(),
          poll(voted: true),
          poll(closed: true, hidden: true),
          poll(ended: true),
          poll(hidden: true),
          poll(voted: true, mine: true),
        ]) {
          await mount(tester, data, style: style, brightness: brightness);
          expect(tester.takeException(), isNull);
          expect(find.text('331 人参与'), findsOneWidget);
          expect(tester.binding.transientCallbackCount, 0);
        }
      });
      testWidgets(
        '$style $brightness selection is explicit, busy blocks repeated sends, failure retains choice and success marks mine',
        (tester) async {
          var calls = 0;
          var next = Completer<PollVoteResult>();
          await mount(
            tester,
            poll(),
            style: style,
            brightness: brightness,
            submit: (ids) {
              calls++;
              expect(ids, {'0'});
              return next.future;
            },
          );
          expect(tester.widget<PressScale>(voteButton()).onTap, isNull);
          await tester.tap(find.text('选项 0'));
          await tester.pumpAndSettle();
          await tester.tap(voteButton());
          await tester.pump();
          expect(find.text('投票中'), findsOneWidget);
          expect(calls, 1);
          expect(tester.widget<PressScale>(voteButton()).onTap, isNull);
          next.complete(
            const PollVoteResult(success: false, message: '没有投上，请稍后再试'),
          );
          await tester.pumpAndSettle();
          expect(find.text('重试'), findsOneWidget);
          next = Completer<PollVoteResult>();
          await tester.tap(voteButton());
          await tester.pump();
          next.complete(
            PollVoteResult(success: true, poll: poll(voted: true, mine: true)),
          );
          await tester.pumpAndSettle();
          expect(find.text('✓ 已投票'), findsOneWidget);
          expect(
            find.textContaining('我的选择', findRichText: true),
            findsOneWidget,
          );
          expect(calls, 2);
          expect(tester.binding.transientCallbackCount, 0);
        },
      );
      testWidgets(
        '$style $brightness multiselect full disables unselected and supports deselection',
        (tester) async {
          await mount(
            tester,
            poll(multi: true),
            style: style,
            brightness: brightness,
            submit: (_) => Future.value(const PollVoteResult(success: false)),
          );
          await tester.tap(find.text('选项 0'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('选项 1'));
          await tester.pumpAndSettle();
          expect(find.text('最多选 2 项，已选 2'), findsOneWidget);
          await tester.tap(find.text('选项 2'));
          await tester.pumpAndSettle();
          expect(find.text('最多选 2 项，已选 2'), findsOneWidget);
          await tester.tap(find.text('选项 0'));
          await tester.pumpAndSettle();
          expect(find.text('最多选 2 项，已选 1'), findsOneWidget);
        },
      );
    }
  }
  testWidgets(
    '42 options initially show eight, expand only on request under reduced motion',
    (tester) async {
      await mount(
        tester,
        poll(count: 42, closed: true, hidden: true),
        reduced: true,
      );
      expect(find.text('选项 8'), findsNothing);
      expect(find.text('展开其余 34 项 ⌄'), findsOneWidget);
      await tester.tap(find.text('展开其余 34 项 ⌄'));
      await tester.pumpAndSettle();
      expect(find.text('选项 41'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );
  testWidgets(
    'wrapped options use card radius and hidden results have no invented votes in semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      const text = '这是一段很长的真实选项文字需要换行显示以避免窄屏溢出这是一段很长的选项';
      await mount(
        tester,
        ThreadPoll(
          tid: 1,
          multiple: false,
          action: Uri.parse('https://www.chiphell.com/'),
          resultsAfterVote: true,
          options: const [PollOption(text: text, id: '1')],
        ),
      );
      expect(find.text('投票后可以看到结果'), findsOneWidget);
      expect(find.bySemanticsLabel('$text，单选，未选中'), findsOneWidget);
      final clips = tester.widgetList<ClipRRect>(find.byType(ClipRRect));
      expect(
        clips.any((w) => w.borderRadius == BorderRadius.circular(14)),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );
  Future<void> mountVoters(
    WidgetTester tester,
    VotersRepository repository,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: PollVotersSheet(poll: poll(), repository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'voters option switch and paging append with retry preserving current page',
    (tester) async {
      final repository = VotersRepository();
      await mountVoters(tester, repository);
      expect(find.text('本地会员1'), findsOneWidget);
      repository.error = Exception('offline');
      await tester.tap(find.text('下一页'));
      await tester.pumpAndSettle();
      expect(find.text('本地会员1'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      repository.error = null;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(repository.requests.last, ('a', 2));
      expect(find.text('本地会员2'), findsOneWidget);
      await tester.tap(find.text('选项乙'));
      await tester.pumpAndSettle();
      expect(repository.requests.last, ('b', 1));
      expect(find.text('本地会员2'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'voters empty, source permission and errors never fabricate a list',
    (tester) async {
      final repository = VotersRepository()..empty = true;
      await mountVoters(tester, repository);
      expect(find.text('还没有人投这一项'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      repository.error = const PageMessage(
        PageMessageKind.permissionDenied,
        '此投票不允许查看参与人',
      );
      await mountVoters(tester, repository);
      expect(find.text('此投票不允许查看参与人'), findsOneWidget);
      expect(find.text('本地会员1'), findsNothing);
    },
  );
  testWidgets(
    'voters page rollback stops pagination without duplicating names',
    (tester) async {
      final repository = VotersRepository()..rollback = true;
      await mountVoters(tester, repository);
      await tester.tap(find.text('下一页'));
      await tester.pumpAndSettle();
      expect(find.text('本地会员1'), findsOneWidget);
      expect(find.text('下一页'), findsNothing);
    },
  );
}
