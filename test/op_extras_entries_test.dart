import 'package:chh_app/core/reading_prefs.dart';
import 'package:chh_app/data/post_interaction_repository.dart';
import 'package:chh_app/design/feedback.dart';
import 'package:chh_app/design/reading.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/di.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/models/post_interaction.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/pages/thread_detail_page.dart';
import 'package:chh_app/parser/header_parser.dart';
import 'package:chh_app/ui/reading_bar.dart';
import 'package:chh_app/ui/sheet_scaffold.dart';
import 'package:chh_app/widgets/composer_sheet.dart';
import 'package:chh_app/widgets/post_interaction_sheet.dart';
import 'package:chh_app/widgets/post_feedback.dart';
import 'package:chh_app/widgets/thread_comment_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Interactions extends PostInteractionRepository {
  _Interactions({this.denied = false}) : super(ChhClient(fetchers: []));

  final bool denied;
  final ratingReads = <int>[];
  final commentReads = <int>[];
  int sends = 0;

  @override
  Future<PostRateForm> rateForm({
    required int tid,
    required int pid,
    Uri? pageUrl,
  }) async {
    ratingReads.add(pid);
    if (denied) {
      throw const PostInteractionException(
        PostResult(PostResultKind.permissionDenied, '本地权限样例'),
      );
    }
    return PostRateForm(
      tid: tid,
      pid: pid,
      action: Uri.parse('https://www.chiphell.com/forum.php'),
      pageUrl: Uri.parse('https://www.chiphell.com/forum.php'),
      formhash: 'local-only',
      sessionIdentity: chhSession.badges.uid!,
      sessionRevision: chhSession.identityRevision,
      scoreTypes: const [
        RateScoreType(
          fieldName: 'score1',
          label: '邪恶指数',
          min: -2,
          max: 2,
          remaining: 2,
        ),
      ],
    );
  }

  @override
  Future<PostCommentForm> commentForm({
    required int tid,
    required int pid,
    Uri? pageUrl,
  }) async {
    commentReads.add(pid);
    return PostCommentForm(
      tid: tid,
      pid: pid,
      action: Uri.parse('https://www.chiphell.com/forum.php'),
      pageUrl: Uri.parse('https://www.chiphell.com/forum.php'),
      formhash: 'local-only',
    );
  }

  @override
  Future<PostResult> submitComment({
    required PostCommentForm form,
    required String message,
  }) async {
    sends++;
    throw StateError('Entry regression must not submit.');
  }

  @override
  Future<PostResult> submitRating({
    required PostRateForm form,
    required Map<String, int> scores,
    String reason = '',
    bool notify = false,
  }) async {
    sends++;
    throw StateError('Entry regression must not submit.');
  }
}

Future<void> _mount(
  WidgetTester tester,
  _Interactions interactions, {
  bool deniedComment = false,
  ReadingLayout layout = ReadingLayout.comfy,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('chh/update'),
    (call) async => null,
  );
  addTearDown(() {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('chh/update'),
      null,
    );
  });
  final oldLoggedIn = chhSession.loggedIn;
  final oldBadges = chhSession.badges;
  chhSession.loggedIn = true;
  chhSession.badges = const HeaderBadges(
    uid: '99',
    userName: '本地账号',
    notices: 0,
    messages: 0,
  );
  addTearDown(() {
    chhSession.loggedIn = oldLoggedIn;
    chhSession.badges = oldBadges;
  });
  final prefs = ReadingPrefsController(directory: () async => null);
  await prefs.set(ReadingPrefs(layout: layout));
  addTearDown(prefs.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      builder: (_, child) => ReadingScope(controller: prefs, child: child!),
      home: ThreadDetailPage(
        tid: 123,
        title: '主楼入口样例',
        interactions: interactions,
        submitReply:
            ({
              required tid,
              required fid,
              required message,
              quotePid,
              page = 1,
            }) async => throw StateError('Entry regression must not reply.'),
        loadPage: (_, _, _) async => ThreadDetail(
          tid: 123,
          fid: 290,
          title: '主楼入口样例',
          posts: [
            Post(
              pid: 1,
              floor: 1,
              author: '本地楼主',
              authorUid: '1',
              timeRaw: '',
              content: const [TextBlock('主楼正文')],
              actions: PostActionCapabilities(
                comment: deniedComment
                    ? PostActionPermission.denied
                    : PostActionPermission.allowed,
              ),
              rating: const PostRating(
                summary: ['参与人数 1', '邪恶指数 +2'],
                entries: [RatingEntry(user: '评分人', score: '+2')],
              ),
              comments: const [PostComment(author: '点评人', text: '已存在点评')],
            ),
          ],
          page: const PageInfo(current: 1, hasNext: false),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _menuText(String label) =>
    find.descendant(of: find.byType(SheetScaffold), matching: find.text(label));

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('post-more-1')));
  await tester.pumpAndSettle();
  for (final label in ['回复', '点评', '评分']) {
    expect(_menuText(label).hitTestable(), findsOneWidget);
  }
}

void main() {
  testWidgets('opening menu retains all three actions without footer pills', (
    tester,
  ) async {
    final repository = _Interactions();
    await _mount(tester, repository);
    for (final action in ['回复', '点评', '评分']) {
      for (final label in ['回复', '点评', '评分']) {
        expect(find.text(label), findsNothing);
      }
      expect(find.text('已存在点评'), findsOneWidget);
      expect(find.byType(ThreadCommentHeading), findsOneWidget);
      expect(
        tester.getTopLeft(find.byType(ThreadCommentHeading)).dy -
            tester.getBottomLeft(find.byType(OpeningFeedback)).dy +
            FeedbackMetrics.bottom,
        closeTo(34, .01),
      );
      await _openMenu(tester);
      expect(repository.ratingReads.last, 1);
      final checkedCount = repository.ratingReads.length;
      await tester.tap(_menuText(action));
      await tester.pumpAndSettle();
      if (action == '回复') {
        expect(find.byType(ComposerSheet), findsOneWidget);
        expect(find.text('回复 本地楼主'), findsOneWidget);
        expect(repository.commentReads, isEmpty);
      } else {
        final sheet = tester.widget<PostInteractionSheet>(
          find.byType(PostInteractionSheet),
        );
        expect(sheet.post.pid, 1);
        expect(
          sheet.kind,
          action == '点评'
              ? PostInteractionKind.comment
              : PostInteractionKind.rating,
        );
        expect(repository.commentReads, [1]);
        expect(
          repository.ratingReads.length,
          checkedCount,
          reason: 'Reuse the checked form.',
        );
      }
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.byType(ComposerSheet), findsNothing);
      expect(find.byType(PostInteractionSheet), findsNothing);
      expect(repository.sends, 0);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('compact reading retains the 34dp opening-to-comments gap', (
    tester,
  ) async {
    await _mount(tester, _Interactions(), layout: ReadingLayout.compact);
    expect(
      tester.getTopLeft(find.byType(ThreadCommentHeading)).dy -
          tester.getBottomLeft(find.byType(OpeningFeedback)).dy +
          FeedbackMetrics.bottom,
      closeTo(34, .01),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening menu preserves comment and rating permission denials', (
    tester,
  ) async {
    final repository = _Interactions(denied: true);
    await _mount(tester, repository, deniedComment: true);
    await _openMenu(tester);
    expect(find.text('此楼层无法点评'), findsOneWidget);
    expect(find.text('此楼层无评分权限'), findsOneWidget);
    for (final label in ['点评', '评分']) {
      await tester.tap(_menuText(label));
      await tester.pumpAndSettle();
      expect(find.text('更多操作'), findsOneWidget);
      expect(find.byType(PostInteractionSheet), findsNothing);
    }
    expect(repository.ratingReads, [1]);
    expect(repository.commentReads, isEmpty);
    expect(repository.sends, 0);
    await tester.tap(_menuText('回复'));
    await tester.pumpAndSettle();
    expect(find.byType(ComposerSheet), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });

  testWidgets('reading bar write reply remains a reachable unquoted composer', (
    tester,
  ) async {
    final repository = _Interactions();
    await _mount(tester, repository);
    final compose = find.descendant(
      of: find.byType(ReadingBar),
      matching: find.text('写回复…'),
    );
    expect(compose.hitTestable(), findsOneWidget);
    await tester.tap(compose);
    await tester.pumpAndSettle();
    expect(find.byType(ComposerSheet), findsOneWidget);
    expect(find.text('回复 本地楼主'), findsNothing);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(repository.ratingReads, isEmpty);
    expect(repository.commentReads, isEmpty);
    expect(repository.sends, 0);
    expect(tester.takeException(), isNull);
  });
}
