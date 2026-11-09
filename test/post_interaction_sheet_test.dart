import 'dart:async';
import 'package:chh_app/data/post_interaction_drafts.dart';
import 'package:chh_app/data/post_interaction_repository.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/models/post_interaction.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/ui/app_button.dart';
import 'package:chh_app/widgets/post_interaction_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smooth_sheets/smooth_sheets.dart';

class _Repository extends PostInteractionRepository {
  _Repository() : super(ChhClient(fetchers: []));
  int sends = 0;
  int ratingReads = 0;
  Future<PostResult> Function()? send;
  Future<void>? load;
  PostInteractionException? loadFailure;

  Future<void> _waitForForm() async {
    await load;
    if (loadFailure case final failure?) throw failure;
  }

  @override
  Future<PostCommentForm> commentForm({
    required int tid,
    required int pid,
    Uri? pageUrl,
  }) async {
    await _waitForForm();
    return PostCommentForm(
      tid: tid,
      pid: pid,
      action: Uri.parse('https://www.chiphell.com/forum.php'),
      pageUrl: Uri.parse('https://www.chiphell.com/'),
      formhash: 'fake',
      maxLength: 200,
    );
  }

  @override
  Future<PostRateForm> rateForm({
    required int tid,
    required int pid,
    Uri? pageUrl,
  }) async {
    ratingReads++;
    await _waitForForm();
    return PostRateForm(
      tid: tid,
      pid: pid,
      action: Uri.parse('https://www.chiphell.com/forum.php'),
      pageUrl: Uri.parse('https://www.chiphell.com/'),
      formhash: 'fake',
      scoreTypes: const [
        RateScoreType(
          fieldName: 'score1',
          label: '邪恶指数',
          min: -3,
          max: 3,
          remaining: 2,
          options: [-2, 1, 2],
        ),
        RateScoreType(
          fieldName: 'score8',
          label: '门户文章',
          min: 0,
          max: 0,
          remaining: 0,
        ),
      ],
      reasons: const [],
    );
  }

  @override
  Future<PostResult> submitComment({
    required PostCommentForm form,
    required String message,
  }) {
    sends++;
    return send?.call() ??
        Future.value(const PostResult(PostResultKind.failed, '测试失败'));
  }

  @override
  Future<PostResult> submitRating({
    required PostRateForm form,
    required Map<String, int> scores,
    String reason = '',
    bool notify = false,
  }) {
    sends++;
    return send?.call() ??
        Future.value(const PostResult(PostResultKind.failed, '测试失败'));
  }
}

Future<void> _open(
  WidgetTester tester,
  _Repository repo, {
  PostInteractionKind kind = PostInteractionKind.comment,
  PostInteractionDraftStore? store,
  double width = 390,
  double scale = 1,
  ValueNotifier<int>? revision,
  bool waitForForm = true,
  bool reducedMotion = true,
  PostRateForm? initialRatingForm,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 844);
  tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetViewPadding);
  addTearDown(tester.view.resetViewInsets);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: reducedMotion,
        ),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showPostInteractionSheet(
              context,
              kind: kind,
              tid: 7,
              post: const Post(
                pid: 9,
                floor: 2,
                author: '作者',
                timeRaw: '',
                content: [],
              ),
              repository: repo,
              initialRatingForm: initialRatingForm,
              sessionIdentity: () => 'alice',
              sessionRevision: revision == null ? null : () => revision.value,
              sessionChanges: revision,
              drafts: store ?? PostInteractionDraftStore(),
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  if (waitForForm) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }
}

void _expectVisible(WidgetTester tester, Finder finder, {double bottom = 820}) {
  expect(finder, findsOneWidget);
  final rect = tester.getRect(finder);
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.top, greaterThanOrEqualTo(24));
  expect(rect.right, lessThanOrEqualTo(tester.view.physicalSize.width));
  expect(rect.bottom, lessThanOrEqualTo(bottom));
}

void main() {
  for (final sameSession in [true, false]) {
    testWidgets(
      'prechecked rating form is reused only for the same session: $sameSession',
      (tester) async {
        final repo = _Repository();
        final form = PostRateForm(
          tid: 7,
          pid: 9,
          action: Uri.parse(
            'https://www.chiphell.com/forum.php?mod=misc&action=rate',
          ),
          pageUrl: Uri.parse(
            'https://www.chiphell.com/forum.php?mod=misc&action=rate&tid=7&pid=9',
          ),
          formhash: 'fixture',
          sessionIdentity: sameSession ? 'alice' : 'old-account',
          scoreTypes: const [
            RateScoreType(
              fieldName: 'score1',
              label: '邪恶指数',
              min: -3,
              max: 3,
              remaining: 2,
            ),
          ],
        );
        await _open(
          tester,
          repo,
          kind: PostInteractionKind.rating,
          initialRatingForm: form,
        );
        expect(repo.ratingReads, sameSession ? 0 : 1);
        expect(repo.sends, 0);
        expect(find.text('评分'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final kind in PostInteractionKind.values) {
    for (final narrow in [false, true]) {
      testWidgets('real $kind route opens fully before and after async load '
          '${narrow ? 'at 320 width and 2x type' : 'at standard size'}', (
        tester,
      ) async {
        final load = Completer<void>();
        final repo = _Repository()..load = load.future;
        await _open(
          tester,
          repo,
          kind: kind,
          width: narrow ? 320 : 390,
          scale: narrow ? 2 : 1,
          waitForForm: false,
          reducedMotion: narrow,
        );
        expect(
          ModalRoute.of(tester.element(find.byType(PostInteractionSheet))),
          isA<ModalSheetRoute<PostResult>>(),
        );
        final scaffold = find.byType(SheetContentScaffold);
        final initialTop = tester.getTopLeft(scaffold).dy;
        expect(initialTop, closeTo(32, .01));
        _expectVisible(tester, find.text('取消'));
        _expectVisible(tester, find.byKey(const ValueKey('interaction-send')));
        _expectVisible(tester, find.text('作者 / #2'));
        _expectVisible(tester, find.byType(CircularProgressIndicator));

        load.complete();
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(scaffold).dy, closeTo(initialTop, .01));
        _expectVisible(
          tester,
          find.text(kind == PostInteractionKind.comment ? '点评' : '评分'),
        );
        if (kind == PostInteractionKind.comment) {
          _expectVisible(
            tester,
            find.byKey(const ValueKey('interaction-comment')),
          );
          _expectVisible(tester, find.text('0 / 200'));
        } else {
          _expectVisible(tester, find.text('邪恶指数'));
          _expectVisible(
            tester,
            find.byKey(const ValueKey('interaction-score')),
          );
          _expectVisible(tester, find.text('评分理由'));
          if (!narrow) {
            _expectVisible(
              tester,
              find.byKey(const ValueKey('interaction-reason')),
            );
            _expectVisible(tester, find.text('通知对方评分理由'));
          }
          await tester.ensureVisible(find.text('通知对方评分理由'));
          await tester.pumpAndSettle();
          _expectVisible(tester, find.text('通知对方评分理由'));
        }
        expect(tester.takeException(), isNull);
        expect(repo.sends, 0);
      });
    }

    testWidgets(
      'real $kind route shows async permission error without dragging',
      (tester) async {
        final load = Completer<void>();
        final repo = _Repository()
          ..load = load.future
          ..loadFailure = const PostInteractionException(
            PostResult(PostResultKind.permissionDenied, '当前账号没有操作权限'),
          );
        await _open(
          tester,
          repo,
          kind: kind,
          width: 320,
          scale: 2,
          waitForForm: false,
        );
        load.complete();
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(find.byType(SheetContentScaffold)).dy,
          closeTo(32, .01),
        );
        _expectVisible(tester, find.text('当前账号没有操作权限'));
        _expectVisible(tester, find.text('重新读取'));
        _expectVisible(tester, find.text('取消'));
        expect(tester.takeException(), isNull);
        expect(repo.sends, 0);
      },
    );
  }

  testWidgets('full comment route keeps controls above keyboard after focus', (
    tester,
  ) async {
    final repo = _Repository();
    await _open(tester, repo, width: 320, scale: 2);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    final editor = find.byKey(const ValueKey('interaction-comment'));
    await tester.tap(editor);
    await tester.pumpAndSettle();
    _expectVisible(
      tester,
      find.byKey(const ValueKey('interaction-send')),
      bottom: 544,
    );
    expect(editor.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(repo.sends, 0);
  });

  testWidgets(
    'same UID with a new authentication revision invalidates the form',
    (tester) async {
      final revision = ValueNotifier<int>(1);
      addTearDown(revision.dispose);
      final repo = _Repository();
      await _open(tester, repo, revision: revision);
      await tester.enterText(
        find.byKey(const ValueKey('interaction-comment')),
        '会话草稿',
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AppButton>(find.byKey(const ValueKey('interaction-send')))
            .onPressed,
        isNotNull,
      );
      revision.value = 2;
      await tester.pumpAndSettle();
      expect(find.text('账号已变化，请关闭后重新打开'), findsOneWidget);
      expect(
        tester
            .widget<AppButton>(find.byKey(const ValueKey('interaction-send')))
            .onPressed,
        isNull,
      );
      expect(repo.sends, 0);
    },
  );

  testWidgets('send is locked while pending; failure retains text', (
    tester,
  ) async {
    final repo = _Repository();
    final c = Completer<PostResult>();
    repo.send = () => c.future;
    await _open(tester, repo);
    await tester.enterText(
      find.byKey(const ValueKey('interaction-comment')),
      '保留草稿',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('interaction-send')));
    await tester.pump();
    await tester.pump();
    expect(repo.sends, 1);
    expect(
      tester
          .widget<AppButton>(find.byKey(const ValueKey('interaction-send')))
          .onPressed,
      isNull,
    );
    c.complete(const PostResult(PostResultKind.failed, '测试失败'));
    await tester.pumpAndSettle();
    expect(find.text('保留草稿'), findsOneWidget);
    expect(find.text('测试失败'), findsOneWidget);
  });
  testWidgets('only evil is shown and remaining quota constrains score', (
    tester,
  ) async {
    await _open(tester, _Repository(), kind: PostInteractionKind.rating);
    expect(find.text('门户文章'), findsNothing);
    final field = find.byKey(const ValueKey('interaction-score'));
    expect(tester.widget<TextField>(field).controller!.text, '0');
    await tester.enterText(field, '3');
    await tester.pump();
    expect(find.text('超过剩余可用额度 2'), findsOneWidget);
    expect(
      tester
          .widget<AppButton>(find.byKey(const ValueKey('interaction-send')))
          .onPressed,
      isNull,
    );
    await tester.enterText(field, '-2');
    await tester.pump();
    expect(
      tester
          .widget<AppButton>(find.byKey(const ValueKey('interaction-send')))
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('interaction-reason')))
          .controller!
          .text,
      isEmpty,
    );
  });
  testWidgets(
    'persisted uncertainty prevents retry until explicit acknowledgement',
    (tester) async {
      final store = PostInteractionDraftStore();
      await store.put(
        PostInteractionDraftStore.key('alice', 7, 9, 'comment'),
        const PostInteractionDraft(text: '未确认', uncertain: true),
      );
      final repo = _Repository();
      await _open(tester, repo, store: store);
      expect(
        tester
            .widget<AppButton>(find.byKey(const ValueKey('interaction-send')))
            .onPressed,
        isNull,
      );
      expect(find.text('我已确认未发表，重新编辑'), findsOneWidget);
      expect(repo.sends, 0);
    },
  );
  testWidgets('320 width and 2x type remain scrollable without layout errors', (
    tester,
  ) async {
    await _open(
      tester,
      _Repository(),
      kind: PostInteractionKind.rating,
      width: 320,
      scale: 2,
    );
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('通知对方评分理由'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
