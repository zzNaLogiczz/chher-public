import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chh_app/data/history_index.dart';
import 'package:chh_app/data/user_block_index.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/di.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:chh_app/pages/follow_block_page.dart';
import 'package:chh_app/pages/thread_detail_page.dart';

import 'support/inline_forum_parser.dart';

const _source = BlockedUserSource(
  tid: 2345,
  pid: 234567,
  floor: 5,
  title: '显卡交流',
  excerpt: '这是一段可搜索的来源摘录',
);

Future<void> _selectBlacklist(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text('黑名单'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('narrow large text keeps identity and separate unblock usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final index = UserBlockIndex.forTesting(null);
    await index.block(
      uid: '42',
      name: '非常长的用户昵称非常长的用户昵称',
      blockedAt: DateTime(2024, 11, 4),
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: FollowBlockPage(blocks: index),
      ),
    );
    await _selectBlacklist(tester);
    expect(find.textContaining('2024年11月4日加入'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final unblock = find.byKey(const ValueKey('unblock-42'));
    expect(tester.getSize(unblock).height, greaterThanOrEqualTo(44));
    await tester.pumpWidget(const SizedBox());
    index.dispose();
  });
  testWidgets('empty list hides search', (tester) async {
    final index = UserBlockIndex.forTesting(null);
    await tester.pumpWidget(MaterialApp(home: FollowBlockPage(blocks: index)));
    await tester.pumpAndSettle();
    expect(find.text('还没有关注任何人'), findsOneWidget);
    expect(find.text('黑名单为空'), findsNothing);
    await _selectBlacklist(tester);
    expect(find.text('还没有关注任何人'), findsNothing);
    expect(find.text('黑名单为空'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.pumpWidget(const SizedBox());
    index.dispose();
  });

  testWidgets('switching accounts closes the previous block note editor', (
    tester,
  ) async {
    final index = UserBlockIndex.forTesting(null);
    addTearDown(index.dispose);
    await index.block(uid: '42', name: '账号 A 的条目', note: '账号 A 的备注');
    await tester.pumpWidget(MaterialApp(home: FollowBlockPage(blocks: index)));
    await _selectBlacklist(tester);
    await tester.tap(find.text('账号 A 的条目'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('编辑备注'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '写点什么'), findsOneWidget);

    await index.setUid('901');
    await index.block(uid: '42', name: '账号 B 的条目', note: '账号 B 的备注');
    await tester.pumpAndSettle();
    expect(find.text('账号 B 的条目'), findsOneWidget);
    expect(find.text('账号 B 的备注'), findsOneWidget);
    expect(find.text('账号 A 的条目'), findsNothing);
    expect(find.text('账号 A 的备注'), findsNothing);
    expect(find.widgetWithText(TextField, '写点什么'), findsNothing);
  });

  testWidgets('search by UID, clear search and unblock reactively', (
    tester,
  ) async {
    final index = UserBlockIndex.forTesting(null);
    await index.block(uid: '42', name: '示例作者');
    await tester.pumpWidget(MaterialApp(home: FollowBlockPage(blocks: index)));
    await _selectBlacklist(tester);
    expect(find.text('示例作者'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '不存在');
    await tester.pumpAndSettle();
    expect(find.text('没有找到匹配的用户'), findsOneWidget);
    await tester.tap(find.text('清空搜索'));
    await tester.pumpAndSettle();
    expect(find.text('示例作者'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '42');
    await tester.pumpAndSettle();
    expect(find.text('示例作者'), findsOneWidget);
    final original = index.entries.single;
    expect(find.textContaining('UID 42'), findsOneWidget);
    await tester.tap(find.text('解除'));
    await tester.pumpAndSettle();
    expect(index.entries, isEmpty);
    expect(find.text('黑名单为空'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(index.entries.single.blockedAt, original.blockedAt);
    expect(find.text('示例作者'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    index.dispose();
  });

  testWidgets('search highlights nickname, note, UID and source excerpt', (
    tester,
  ) async {
    final index = UserBlockIndex.forTesting(null);
    await index.block(uid: '1242', name: '广告用户', note: '反复发布 广告');
    await index.block(uid: '65', name: '来源用户', src: _source);
    await tester.pumpWidget(MaterialApp(home: FollowBlockPage(blocks: index)));
    await _selectBlacklist(tester);

    final search = find.byType(TextField);
    final accent = AppTokens.of(tester.element(search)).accent;
    void expectHighlight(Finder text, String match, int offset) {
      final span = tester.widget<Text>(text).textSpan!;
      final found = span.getSpanForPosition(TextPosition(offset: offset))!;
      expect(found.toPlainText(), match);
      expect(found.style?.color, accent);
    }

    await tester.enterText(search, '广告');
    await tester.pumpAndSettle();
    expectHighlight(find.text('广告用户'), '广告', 1);
    expect(find.text('来源用户'), findsNothing);

    await tester.enterText(search, '反复');
    await tester.pumpAndSettle();
    expectHighlight(find.text('反复发布 广告'), '反复', 1);
    expect(find.text('广告用户'), findsOneWidget);
    expect(find.text('来源用户'), findsNothing);

    await tester.enterText(search, '42');
    await tester.pumpAndSettle();
    expectHighlight(find.textContaining('UID 1242'), '42', 7);
    expect(find.text('广告用户'), findsOneWidget);
    expect(find.text('来源用户'), findsNothing);

    await tester.enterText(search, '来源摘录');
    await tester.pumpAndSettle();
    expectHighlight(find.text('“${_source.excerpt}”'), '来源摘录', 11);
    expect(find.text('来源用户'), findsOneWidget);
    expect(find.text('广告用户'), findsNothing);
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.tap(find.byTooltip('清除搜索'));
    await tester.pumpAndSettle();
    final editor = tester.widget<TextField>(search);
    expect(editor.controller!.text, isEmpty);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
    await tester.pumpWidget(const SizedBox());
    index.dispose();
  });

  testWidgets('detail edits a note in place and keeps the original source', (
    tester,
  ) async {
    final index = UserBlockIndex.forTesting(null);
    final date = DateTime(2026, 11, 4);
    tester.view.physicalSize = const Size(320, 680);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await index.block(
      uid: '42',
      name: '示例作者',
      note: '原有备注',
      blockedAt: date,
      src: _source,
    );
    await tester.pumpWidget(MaterialApp(home: FollowBlockPage(blocks: index)));
    await _selectBlacklist(tester);

    await tester.enterText(find.byType(TextField), '来源摘录');
    await tester.pumpAndSettle();
    expect(find.text('原有备注'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('查看 示例作者 的黑名单详情')), findsOneWidget);
    expect(find.bySemanticsLabel('解除 示例作者 的黑名单'), findsOneWidget);
    expect(find.text(_source.excerpt), findsNothing);
    await tester.tap(find.text('示例作者'));
    await tester.pumpAndSettle();
    expect(find.text('《${_source.title}》'), findsOneWidget);
    expect(find.text('#5'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('打开来源，《显卡交流》，#5')), findsOneWidget);
    final excerpt = find.text(_source.excerpt);
    expect(excerpt, findsOneWidget);
    expect(
      tester
          .widget<Text>(excerpt)
          .textSpan!
          .getSpanForPosition(const TextPosition(offset: 10))
          ?.toPlainText(),
      '来源摘录',
    );
    expect(find.text('查看主页'), findsOneWidget);
    expect(find.text('解除黑名单'), findsOneWidget);
    await tester.tap(find.byTooltip('编辑备注'));
    tester.view.viewInsets = const FakeViewPadding(bottom: 290);
    await tester.pumpAndSettle();
    final editor = find.widgetWithText(TextField, '写点什么');
    expect(editor, findsOneWidget);
    expect(tester.widget<TextField>(editor).controller!.text, '原有备注');
    expect(tester.testTextInput.isVisible, isTrue);
    expect(tester.getBottomLeft(editor).dy, lessThanOrEqualTo(680 - 290));
    expect(editor.hitTestable(), findsOneWidget);
    await tester.enterText(editor, '更新后的备注');
    final save = find.text('完成');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final saved = index.entryFor('42')!;
    expect(saved.note, '更新后的备注');
    expect(saved.blockedAt, date);
    expect(saved.src!.pid, _source.pid);
    expect(saved.src!.excerpt, _source.excerpt);
    expect(editor, findsNothing);
    expect(find.text('查看主页'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('更新后的备注'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    index.dispose();
  });

  testWidgets('source card closes detail and locates the hidden reply', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final index = UserBlockIndex.forTesting(null);
    const source = BlockedUserSource(
      tid: 900001,
      pid: 90000109,
      floor: 9,
      title: '拉黑来源的帖子',
      excerpt: '最后一楼的摘录',
    );
    await index.block(uid: '1009', name: '示例回复者8', src: source);
    useInlineForumParser(chhClient);
    final oldFetchers = List<ChhFetcher>.of(chhClient.fetchers);
    final fake = _BlockedSourceFetcher(
      File('test_data/thread_synthetic.html').readAsStringSync(),
    );
    chhClient.clearCache();
    chhClient.fetchers
      ..clear()
      ..add(fake);
    addTearDown(() async {
      chhClient.fetchers
        ..clear()
        ..addAll(oldFetchers);
      chhClient.clearCache();
      await historyIndex.clear();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: FollowBlockPage(blocks: index),
      ),
    );
    await _selectBlacklist(tester);
    await tester.tap(find.text('示例回复者8'));
    await tester.pumpAndSettle();
    final sourceCard = find.text('《${source.title}》');
    await tester.tap(sourceCard);
    await tester.pumpAndSettle();

    expect(sourceCard, findsNothing);
    expect(find.byType(ThreadDetailPage), findsOneWidget);
    expect(
      fake.requests.first.queryParameters,
      containsPair('pid', '${source.pid}'),
    );
    expect(
      fake.requests.first.queryParameters,
      containsPair('goto', 'findpost'),
    );
    expect(
      fake.requests.first.queryParameters,
      containsPair('ptid', '${source.tid}'),
    );
    expect(find.text('已屏蔽 · 示例回复者8').hitTestable(), findsOneWidget);
    expect(find.textContaining('合成正文，编号9', findRichText: true), findsNothing);
    await tester.pumpWidget(const SizedBox());
    index.dispose();
  });
}

class _BlockedSourceFetcher extends ChhFetcher {
  final String html;
  final requests = <Uri>[];

  _BlockedSourceFetcher(this.html);

  @override
  String get name => 'blocked-source-fixture';

  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) async {
    requests.add(url);
    return ChhResponse(200, html);
  }
}
