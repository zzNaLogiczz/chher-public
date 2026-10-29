import 'dart:io';

import 'package:chh_app/design/theme.dart';
import 'package:chh_app/di.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:chh_app/pages/thread_detail_page.dart';
import 'package:chh_app/parser/thread_parser.dart';
import 'package:chh_app/widgets/composer_sheet.dart';
import 'package:chh_app/widgets/post_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ThreadFixtureFetcher implements ChhFetcher {
  _ThreadFixtureFetcher(this.html);
  final String html;
  int posts = 0;

  @override
  String get name => 'thread-fixture';
  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) async =>
      ChhResponse(200, html);
  @override
  Future<ChhResponse> postForm(Uri url, Map<String, String> form) async {
    posts++;
    throw StateError('This test must never submit a reply.');
  }

  @override
  Future<ChhResponse> postMultipart(
    Uri url,
    Map<String, String> fields,
    UploadFile file,
  ) async {
    throw StateError('This test must never upload.');
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  final sample = File('test_data/thread_synthetic.html').readAsStringSync();
  const tid = 900001;

  group('thread fid from authoritative page structure', () {
    test('synthetic forum 290 fixture resolves its current reply form', () {
      expect(parseThread(sample, tid: tid).fid, 290);
    });

    test('guest page without a reply form resolves the breadcrumb', () {
      final html = sample.replaceAll(
        RegExp(r'<form\b[^>]*id="(?:fastpostform|postform)"[\s\S]*?</form>'),
        '',
      );
      expect(parseThread(html, tid: tid).fid, 290);
    });

    test('a reply form still works when no breadcrumb is present', () {
      const html =
          '<form id="fastpostform" action="forum.php?mod=post&amp;'
          'action=reply&amp;tid=900001&amp;fid=290"></form>';
      expect(parseThread(html, tid: tid).fid, 290);
    });

    test('current reply form takes precedence over parent navigation', () {
      const html =
          '<div id="pt"><a href="forum-223-1.html">父版块</a></div>'
          '<form id="fastpostform" action="forum.php?mod=post&amp;'
          'action=reply&amp;tid=900001&amp;fid=290"></form>';
      expect(parseThread(html, tid: tid).fid, 290);
    });

    test('deepest breadcrumb accepts query-string forum URLs', () {
      const html =
          '<div id="pt"><a href="forum-223-1.html">父版块</a>'
          '<a href="forum.php?mod=forumdisplay&amp;fid=290">当前版块</a>'
          '<a href="thread-900001-1-1.html">帖子</a></div>';
      expect(parseThread(html, tid: tid).fid, 290);
    });

    test(
      'unrelated thread form and links in post content are not a fallback',
      () {
        const html =
            '<form id="fastpostform" action="forum.php?mod=post&amp;'
            'action=reply&amp;tid=123&amp;fid=999"></form>'
            '<div id="postlist"><a href="forum-146-1.html">正文链接</a></div>';
        expect(parseThread(html, tid: tid).fid, isNull);
      },
    );

    test('invalid or offsite identifiers are not accepted', () {
      const html =
          '<div id="pt"><a href="https://example.com/forum-999-1.html">'
          '外站</a><a href="forum-0-1.html">无效</a></div>';
      expect(parseThread(html, tid: tid).fid, isNull);
    });
  });

  group('reply entry without a pre-supplied fid', () {
    late List<ChhFetcher> originalFetchers;
    late _ThreadFixtureFetcher fixture;

    setUp(() {
      originalFetchers = List.of(chhClient.fetchers);
      fixture = _ThreadFixtureFetcher(sample);
      chhClient.clearCache();
      chhClient.fetchers
        ..clear()
        ..add(fixture);
    });
    tearDown(() {
      chhClient.clearCache();
      chhClient.fetchers
        ..clear()
        ..addAll(originalFetchers);
    });

    Future<void> openThread(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: const ThreadDetailPage(tid: tid, title: '合成样本'),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('article-style entry can open the normal reply composer', (
      tester,
    ) async {
      await openThread(tester);
      await tester.tap(find.text('写回复…'));
      await tester.pumpAndSettle();
      expect(find.byType(ComposerSheet), findsOneWidget);
      expect(find.text('缺少版块信息,请从版块列表进入后回复'), findsNothing);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(fixture.posts, 0);
    });

    testWidgets(
      'quote reply resolves the same page fid and preserves the quote',
      (tester) async {
        await openThread(tester);
        final opening = tester.widget<PostCard>(find.byType(PostCard).first);
        opening.onReply!();
        await tester.pumpAndSettle();
        expect(find.byType(ComposerSheet), findsOneWidget);
        expect(find.text('引用 示例作者甲 #1'), findsOneWidget);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(fixture.posts, 0);
      },
    );
  });
}
