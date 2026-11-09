import 'dart:async';

import 'package:chh_app/data/post_interaction_repository.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/models/post_interaction.dart';
import 'package:chh_app/parser/post_action_parser.dart';
import 'package:chh_app/widgets/post_action_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

Post menuPost() => Post(
  pid: 20,
  floor: 2,
  author: '测试作者',
  authorUid: '25',
  timeRaw: '',
  content: const [],
  actions: parsePostActionCapabilities(
    html
        .parse(
          '<table id="pid20"><tr><td><div class="po"><a href="forum.php?mod=post&action=reply&tid=10&repquote=20">回复</a></div></td></tr></table>',
        )
        .getElementById('pid20')!,
    tid: 10,
    pid: 20,
  ),
);

PostRateForm form({int remaining = 4}) => PostRateForm(
  tid: 10,
  pid: 20,
  action: Uri.parse('https://www.chiphell.com/forum.php?mod=misc&action=rate'),
  pageUrl: interactionPageUrl(PostInteractionKind.rating, 10, 20),
  formhash: 'fixture',
  scoreTypes: [
    RateScoreType(
      fieldName: 'score1',
      label: '邪恶指数',
      min: -4,
      max: 4,
      remaining: remaining,
    ),
  ],
);

Future<void> openMenu(
  WidgetTester tester, {
  required Future<PostRateForm> Function() check,
  bool loggedIn = true,
  bool isSelf = false,
  bool blocked = false,
  bool reducedMotion = false,
  ValueChanged<PostMenuAction?>? selected,
  Listenable? changes,
  String? Function()? identity,
  int Function()? revision,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              final result = await showPostActionMenu(
                context,
                post: menuPost(),
                opening: false,
                loggedIn: loggedIn,
                blocked: blocked,
                isSelf: isSelf,
                checkRating: check,
                sessionChanges: changes,
                sessionIdentity: identity,
                sessionRevision: revision,
              );
              selected?.call(result);
            },
            child: const Text('打开'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('missing rating link preflights before allowing form entry', (
    tester,
  ) async {
    final gate = Completer<PostRateForm>();
    PostMenuAction? selected;
    var calls = 0;
    await openMenu(
      tester,
      check: () {
        calls++;
        return gate.future;
      },
      selected: (value) => selected = value,
    );
    expect(find.text('正在检查评分权限'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('重试'), findsNothing);
    await tester.tap(find.text('评分'));
    await tester.pump();
    expect(selected, isNull);
    expect(calls, 1);
    gate.complete(form());
    await tester.pumpAndSettle();
    expect(find.text('邪恶指数，今日可用 4'), findsOneWidget);
    expect(find.text('当前账号无评分权限'), findsNothing);
    await tester.tap(find.text('评分'));
    await tester.pumpAndSettle();
    expect(selected, PostMenuAction.rating);
  });

  for (final kind in [
    PostResultKind.permissionDenied,
    PostResultKind.failed,
    PostResultKind.ratingQuotaExhausted,
  ]) {
    testWidgets('$kind has no retry button and checks again when reopened', (
      tester,
    ) async {
      var calls = 0;
      PostMenuAction? selected;
      await openMenu(
        tester,
        check: () async {
          if (++calls == 1) {
            throw PostInteractionException(PostResult(kind, 'fixture'));
          }
          return form();
        },
        selected: (value) => selected = value,
      );
      final hint = kind == PostResultKind.permissionDenied
          ? '此楼层无评分权限'
          : kind == PostResultKind.failed
          ? '暂未确认评分权限'
          : '暂无可用评分额度';
      expect(find.text(hint), findsOneWidget);
      expect(find.text('重新检查权限'), findsNothing);
      await tester.tap(find.text('评分'));
      await tester.pumpAndSettle();
      expect(selected, isNull);
      expect(calls, 1);
      expect(find.text('重试'), findsNothing);
      expect(find.byTooltip('重试评分检查'), findsNothing);
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('邪恶指数，今日可用 4'), findsOneWidget);
    });
  }

  for (final self in [false, true]) {
    testWidgets(
      self
          ? 'own post does not request rating form'
          : 'logged out asks for login without GET',
      (tester) async {
        var calls = 0;
        PostMenuAction? selected;
        await openMenu(
          tester,
          loggedIn: self,
          isSelf: self,
          check: () async {
            calls++;
            return form();
          },
          selected: (value) => selected = value,
        );
        expect(find.text(self ? '不能给自己的帖子评分' : '登录后可评分'), findsOneWidget);
        expect(find.text('去登录'), self ? findsNothing : findsOneWidget);
        await tester.tap(find.text('评分'));
        await tester.pumpAndSettle();
        expect(calls, 0);
        expect(selected, self ? isNull : PostMenuAction.login);
      },
    );
  }

  testWidgets('server login denial routes to login even with local auth', (
    tester,
  ) async {
    PostMenuAction? selected;
    await openMenu(
      tester,
      loggedIn: true,
      check: () async => throw const PostInteractionException(
        PostResult(PostResultKind.loginRequired, '请先登录'),
      ),
      selected: (value) => selected = value,
    );
    await tester.tap(find.text('评分'));
    await tester.pumpAndSettle();
    expect(selected, PostMenuAction.login);
  });

  testWidgets('empty quota is distinct from permission denial', (tester) async {
    await openMenu(tester, check: () async => form(remaining: 0));
    expect(find.text('暂无可用评分额度'), findsOneWidget);
    expect(find.text('此楼层无评分权限'), findsNothing);
  });

  testWidgets('server login and self errors are not denied and have no retry', (
    tester,
  ) async {
    for (final kind in [
      PostResultKind.loginRequired,
      PostResultKind.selfRating,
    ]) {
      await openMenu(
        tester,
        check: () async =>
            throw PostInteractionException(PostResult(kind, 'fixture')),
      );
      expect(
        find.text(
          kind == PostResultKind.loginRequired ? '登录后可评分' : '不能给自己的帖子评分',
        ),
        findsOneWidget,
      );
      expect(find.byTooltip('重试评分检查'), findsNothing);
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('reduced motion keeps checking indicator static', (tester) async {
    final gate = Completer<PostRateForm>();
    await openMenu(tester, check: () => gate.future, reducedMotion: true);
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .value,
      .75,
    );
    gate.complete(form());
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('邪恶指数，今日可用 4'), findsOneWidget);
  });

  testWidgets('blocked menu uses recovery label and accent color', (
    tester,
  ) async {
    PostMenuAction? selected;
    await openMenu(
      tester,
      blocked: true,
      check: () async => form(),
      selected: (value) => selected = value,
    );
    final label = find.text('解除黑名单');
    final tokens = AppTokens.of(tester.element(label));
    expect(tester.widget<Text>(label).style?.color, tokens.accent);
    expect(find.text('解除拉黑'), findsNothing);
    await tester.tap(label);
    await tester.pumpAndSettle();
    expect(selected, PostMenuAction.blockUser);
  });

  testWidgets('identity revision change closes menu and discards late GET', (
    tester,
  ) async {
    final changes = ChangeNotifier();
    final gate = Completer<PostRateForm>();
    var revision = 0;
    await openMenu(
      tester,
      check: () => gate.future,
      changes: changes,
      identity: () => 'same-user',
      revision: () => revision,
    );
    changes.notifyListeners();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('更多操作'), findsOneWidget);
    revision++;
    changes.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('更多操作'), findsNothing);
    gate.complete(form());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    changes.dispose();
  });
}
