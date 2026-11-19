import 'dart:async';

import 'package:chh_app/data/rating_repository.dart';
import 'package:chh_app/design/feedback.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:chh_app/pages/source_page_drawer.dart';
import 'package:chh_app/ui/chrome_button.dart';
import 'package:chh_app/widgets/link_opener.dart';
import 'package:chh_app/widgets/chhers_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'op_extras_rating_test.dart' as fixture;

const shortReason = '在用 ...';
const fullReason = '在用，审美很在线，更新得也很勤。这是用于离线测试的完整附言，应该全部显示并与名字左边对齐。';
final detailsUrl = Uri.parse(
  'https://www.chiphell.com/misc.php?mod=viewratings&tid=42&pid=55',
);
PostRating rating({String reason = shortReason}) => PostRating(
  tid: 42,
  pid: 55,
  detailsUrl: detailsUrl,
  summary: const ['参与人数 2', '邪恶指数 +15'],
  entries: [
    RatingEntry(user: '用户0', score: '+10', reason: reason),
    const RatingEntry(user: '用户1', score: '+5', reason: '另一个 ...'),
  ],
);

// Synthetic Discuz X3 viewratings markup; real CHH DOM needs device verification.
const detailsHtml =
    '''<html><body><div class="c"><table class="list" cellspacing="0" cellpadding="0">
<thead><tr><th>积分</th><th>用户名</th><th>时间</th><th>理由</th></tr></thead>
<tbody>
<tr><td>邪恶指数 <span>+10</span></td><td><a href="home.php?mod=space&amp;uid=12">用户0</a></td><td>2026-11-15 10:30</td><td>$fullReason</td></tr>
<tr><td>邪恶指数 +5</td><td><a href="space-uid-13.html">用户1</a></td><td>2026-11-15 10:31</td><td>另一个完整附言。</td></tr>
</tbody>
</table></div></body></html>''';

// A complete page with no known rating template, not an inajax fragment.
const contentDetailsHtml =
    '''<html><head><title>合成评分明细</title></head><body>
<header><a href="space-uid-12.html">用户0</a><p>导航</p></header>
<main><h1>评分记录</h1><div class="records">
<div class="record"><a href="space-uid-12.html">用户0</a><span>邪恶指数 + 10</span><time>2026-11-15 10:30</time><p>$fullReason</p></div>
<div class="record"><a href="space-uid-13.html">用户1</a><span>邪恶指数 +5</span><time>2026-11-15 10:31</time><p>另一个完整附言。</p></div>
</div></main></body></html>''';

class PendingFetcher extends ChhFetcher {
  final response = Completer<ChhResponse>();
  int calls = 0;
  @override
  String get name => 'rating-fixture';
  @override
  Future<ChhResponse> getHtml(Uri uri, {Map<String, String>? headers}) {
    calls++;
    expect(uri, detailsUrl);
    return response.future;
  }
}

Finder bodyText(String text) => find.byWidgetPredicate(
  (w) => w is Text && w.data == text && w.maxLines == null,
);

final _activeSpinner = find.byWidgetPredicate(
  (widget) => widget is ChhersSpinner && widget.active,
);

void main() {
  for (final page in {
    'standard table': detailsHtml,
    'content div': contentDetailsHtml,
  }.entries) {
    testWidgets(
      '${page.key}: pending stays stable, arrival fades and reveals, cache survives remount',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final fetcher = PendingFetcher();
        final repo = RatingRepository(ChhClient(fetchers: [fetcher]));
        await fixture.mount(tester, rating: rating(), repository: repo);
        expect(fetcher.calls, 0);
        await tester.tap(fixture.detailName('用户0'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(fetcher.calls, 1);
        expect(bodyText(shortReason), findsOneWidget);
        expect(_activeSpinner, findsOneWidget);
        expect(
          tester
              .getSemantics(find.bySemanticsLabel('用户0 +10 $shortReason'))
              .getSemanticsData()
              .value,
          '正在读取完整附言',
        );
        final namePosition = tester.getTopLeft(fixture.detailName('用户0'));
        final pendingRowHeight = tester.getSize(fixture.row('用户0')).height;
        await tester.pump(const Duration(seconds: 2));
        expect(tester.getSize(fixture.row('用户0')).height, pendingRowHeight);
        await tester.tap(fixture.detailName('用户1'));
        await tester.pump();
        expect(fetcher.calls, 1);
        final exitingSpinner = find.descendant(
          of: find.descendant(
            of: fixture.row('用户0'),
            matching: find.byType(ChhersSpinner),
          ),
          matching: find.byType(FadeTransition),
        );
        expect(exitingSpinner, findsOneWidget);
        fetcher.response.complete(ChhResponse(200, page.value));
        await tester.pump();
        expect(_activeSpinner, findsNothing);
        expect(bodyText(fullReason), findsOneWidget);
        expect(tester.getSize(fixture.row('用户0')).height, pendingRowHeight);
        final initialAlpha = tester
            .widget<Text>(bodyText(fullReason))
            .style!
            .color!
            .a;
        expect(initialAlpha, 0);
        await tester.pump(const Duration(milliseconds: 90));
        expect(
          tester.widget<FadeTransition>(exitingSpinner).opacity.value,
          inExclusiveRange(0, 1),
        );
        expect(
          tester.widget<Text>(bodyText(fullReason)).style!.color!.a,
          inExclusiveRange(0, 1),
        );
        expect(
          tester.getSize(fixture.row('用户0')).height,
          greaterThan(pendingRowHeight),
        );
        await tester.pump(const Duration(milliseconds: 90));
        expect(tester.widget<Text>(bodyText(fullReason)).style!.color!.a, 1);
        expect(exitingSpinner, findsNothing);
        expect(tester.getTopLeft(fixture.detailName('用户0')), namePosition);
        await tester.pumpAndSettle();
        expect(find.text('在网页中查看'), findsNothing);
        expect(
          tester.getTopLeft(bodyText(fullReason)).dx,
          tester.getTopLeft(fixture.detailName('用户0')).dx,
        );
        expect(bodyText('另一个完整附言。'), findsOneWidget);
        await tester.tap(fixture.detailName('用户0'));
        await tester.pumpAndSettle();
        await tester.tap(fixture.detailName('用户0'));
        await tester.pumpAndSettle();
        expect(fetcher.calls, 1);
        await tester.pumpWidget(const SizedBox());
        await fixture.mount(tester, rating: rating(), repository: repo);
        await tester.tap(fixture.detailName('用户0'));
        await tester.pump();
        expect(bodyText(fullReason), findsOneWidget);
        expect(tester.widget<Text>(bodyText(fullReason)).style!.color!.a, 1);
        expect(_activeSpinner, findsNothing);
        await tester.pumpAndSettle();
        expect(fetcher.calls, 1);
        expect(tester.binding.transientCallbackCount, 0);
        semantics.dispose();
      },
    );
  }

  for (final standard in [true, false]) {
    testWidgets(
      '${standard ? 'standard' : 'content'} table keeps an identical truncated reason without web fallback',
      (tester) async {
        const unchanged = '在用，审美很在线，更新得也很勤 ...';
        final html = detailsHtml
            .replaceAll(fullReason, unchanged)
            .replaceAll(
              'href="home.php?mod=space&amp;uid=12"',
              standard ? 'href="home.php?mod=space&amp;uid=12"' : '',
            );
        final fetcher = PendingFetcher();
        final repo = RatingRepository(ChhClient(fetchers: [fetcher]));
        await fixture.mount(
          tester,
          rating: rating(reason: unchanged),
          repository: repo,
        );
        expect(fetcher.calls, 0);
        await tester.tap(fixture.detailName('用户0'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        final pendingHeight = tester.getSize(fixture.row('用户0')).height;
        expect(bodyText(unchanged), findsOneWidget);
        expect(_activeSpinner, findsOneWidget);
        await tester.pump(const Duration(seconds: 1));
        expect(tester.getSize(fixture.row('用户0')).height, pendingHeight);
        fetcher.response.complete(ChhResponse(200, html));
        await tester.pump();
        await tester.pump();
        expect(bodyText(unchanged), findsOneWidget);
        expect(_activeSpinner, findsNothing);
        expect(find.text('在网页中查看'), findsNothing);
        expect(tester.widget<Text>(bodyText(unchanged)).style!.color!.a, 0);
        await tester.pump(const Duration(milliseconds: 90));
        expect(
          tester.widget<Text>(bodyText(unchanged)).style!.color!.a,
          inExclusiveRange(0, 1),
        );
        await tester.pump(const Duration(milliseconds: 90));
        expect(tester.widget<Text>(bodyText(unchanged)).style!.color!.a, 1);
        await tester.pumpAndSettle();
        expect(tester.getSize(fixture.row('用户0')).height, pendingHeight);
        await tester.tap(fixture.detailName('用户0'));
        await tester.pumpAndSettle();
        await tester.tap(fixture.detailName('用户0'));
        await tester.pumpAndSettle();
        expect(bodyText(unchanged), findsOneWidget);
        expect(find.text('在网页中查看'), findsNothing);
        expect(fetcher.calls, 1);
        await tester.pumpWidget(const SizedBox());
        await fixture.mount(
          tester,
          rating: rating(reason: unchanged),
          repository: repo,
        );
        await tester.tap(fixture.detailName('用户0'));
        await tester.pump();
        expect(bodyText(unchanged), findsOneWidget);
        expect(tester.widget<Text>(bodyText(unchanged)).style!.color!.a, 1);
        expect(_activeSpinner, findsNothing);
        expect(find.text('在网页中查看'), findsNothing);
        await tester.pumpAndSettle();
        expect(fetcher.calls, 1);
        expect(tester.binding.transientCallbackCount, 0);
      },
    );
  }

  testWidgets('rebuilt floor data and repeated taps retain the pending read', (
    tester,
  ) async {
    final fetcher = PendingFetcher();
    final repo = RatingRepository(ChhClient(fetchers: [fetcher]));
    await fixture.mount(
      tester,
      rating: rating(),
      repository: repo,
      reduced: true,
    );
    await tester.tap(fixture.detailName('用户0'));
    await tester.pump();
    await tester.tap(fixture.detailName('用户0'));
    await tester.pumpAndSettle();
    // A new immutable projection of the same floor must not invalidate its read.
    await fixture.mount(
      tester,
      rating: rating(),
      repository: repo,
      reduced: true,
    );
    await tester.tap(fixture.detailName('用户0'));
    await tester.pump();
    expect(fetcher.calls, 1);
    fetcher.response.complete(const ChhResponse(200, detailsHtml));
    await tester.pumpAndSettle();
    expect(bodyText(fullReason), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
  });

  for (final scenario in {
    'request failure': const ChhResponse(-1, '', error: 'offline'),
    'login required': const ChhResponse(
      200,
      '<html><body><div id="messagetext">请先登录</div><form id="loginform"></form></body></html>',
    ),
    'blocked': const ChhResponse(567, 'Invalid Request'),
    'row missing': const ChhResponse(200, '<html><body>无法解析</body></html>'),
    'ambiguous standard table': ChhResponse(
      200,
      detailsHtml.replaceAll('用户1', '用户0').replaceAll('+5', '+10'),
    ),
    'ambiguous content table': ChhResponse(
      200,
      detailsHtml
          .replaceAll('用户1', '用户0')
          .replaceAll('+5', '+10')
          .replaceAll('href="home.php?mod=space&amp;uid=12"', '')
          .replaceAll('href="space-uid-13.html"', ''),
    ),
  }.entries) {
    testWidgets('${scenario.key} keeps original and opens details in app', (
      tester,
    ) async {
      final fetcher = PendingFetcher();
      final repo = RatingRepository(ChhClient(fetchers: [fetcher]));
      final oldLauncher = externalLauncher;
      Uri? opened;
      externalLauncher = (uri) async {
        opened = uri;
        return true;
      };
      addTearDown(() => externalLauncher = oldLauncher);
      final semantics = tester.ensureSemantics();
      await fixture.mount(tester, rating: rating(), repository: repo);
      await tester.tap(fixture.detailName('用户0'));
      await tester.pump();
      fetcher.response.complete(scenario.value);
      await tester.pumpAndSettle();
      expect(bodyText(shortReason), findsOneWidget);
      expect(find.text('在网页中查看'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.bySemanticsLabel('在网页中查看'), findsOneWidget);
      await tester.tap(find.text('在网页中查看'));
      // Stop during the drawer transition, before the native WebView is built.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byType(SourcePageDrawer), findsOneWidget);
      expect(
        tester.widget<SourcePageDrawer>(find.byType(SourcePageDrawer)).url,
        detailsUrl,
      );
      expect(opened, isNull);
      tester
          .widget<ChromeButton>(
            find.byWidgetPredicate(
              (w) => w is ChromeButton && w.tooltip == '关闭原页面',
            ),
          )
          .onPressed!();
      await tester.pumpAndSettle();
      expect(find.byType(SourcePageDrawer), findsNothing);
      expect(bodyText(shortReason), findsOneWidget);
      await tester.tap(fixture.detailName('用户0'));
      await tester.pumpAndSettle();
      await tester.tap(fixture.detailName('用户0'));
      await tester.pumpAndSettle();
      expect(find.text('在网页中查看'), findsOneWidget);
      expect(fetcher.calls, 1);
      expect(tester.binding.transientCallbackCount, 0);
      semantics.dispose();
    });
  }

  testWidgets('UI-only truncation never requests details', (tester) async {
    final fetcher = PendingFetcher();
    final repo = RatingRepository(ChhClient(fetchers: [fetcher]));
    await fixture.mount(
      tester,
      rating: rating(reason: fullReason),
      repository: repo,
    );
    await tester.tap(fixture.detailName('用户0'));
    await tester.pumpAndSettle();
    expect(bodyText(fullReason), findsOneWidget);
    expect(fetcher.calls, 0);
  });

  for (final style in AppearanceStyle.values) {
    for (final brightness in Brightness.values) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'content arrival respects reduced motion and alignment $style $brightness scale=$scale',
          (tester) async {
            final fetcher = PendingFetcher();
            final repo = RatingRepository(ChhClient(fetchers: [fetcher]));
            await fixture.mount(
              tester,
              width: 320,
              scale: scale,
              style: style,
              brightness: brightness,
              reduced: true,
              rating: rating(),
              repository: repo,
            );
            await tester.tap(fixture.detailName('用户0'));
            await tester.pump();
            expect(
              tester.getTopLeft(bodyText(shortReason)).dx,
              tester.getTopLeft(fixture.detailName('用户0')).dx,
            );
            final pendingHeight = tester.getSize(fixture.row('用户0')).height;
            await tester.pump(const Duration(seconds: 1));
            expect(tester.getSize(fixture.row('用户0')).height, pendingHeight);
            fetcher.response.complete(
              const ChhResponse(200, contentDetailsHtml),
            );
            // Flush the completed read, then render without advancing motion.
            await tester.pump();
            await tester.pump();
            expect(bodyText(fullReason), findsOneWidget);
            final arrivedHeight = tester.getSize(fixture.row('用户0')).height;
            expect(arrivedHeight, greaterThan(pendingHeight));
            expect(
              tester.widget<Text>(bodyText(fullReason)).style!.color!.a,
              0,
            );
            await tester.pump(const Duration(milliseconds: 150));
            expect(
              tester.widget<Text>(bodyText(fullReason)).style!.color!.a,
              1,
            );
            await tester.pumpAndSettle();
            expect(tester.getSize(fixture.row('用户0')).height, arrivedHeight);
            expect(
              tester.getTopLeft(bodyText(fullReason)).dx,
              tester.getTopLeft(fixture.detailName('用户0')).dx,
            );
            final text = tester.widget<Text>(bodyText(fullReason));
            expect(text.style!.color, tokensFor(brightness, style).text2);
            expect(text.style!.fontSize, FeedbackMetrics.reasonSize);
            expect(tester.takeException(), isNull);
            expect(tester.binding.transientCallbackCount, 0);
          },
        );
      }
    }
  }
}
