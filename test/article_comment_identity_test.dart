import 'dart:io';

import 'package:chh_app/data/image_disk_cache.dart';
import 'package:chh_app/design/icons.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/di.dart';
import 'package:chh_app/models/article_discussion.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:chh_app/pages/article_discussion_page.dart';
import 'package:chh_app/pages/user_drawer.dart';
import 'package:chh_app/pages/user_page.dart';
import 'package:chh_app/parser/article_comments_parser.dart';
import 'package:chh_app/ui/chrome_button.dart';
import 'package:chh_app/ui/press.dart';
import 'package:chh_app/widgets/article_discussion_widgets.dart';
import 'package:chh_app/widgets/cached_net_image.dart';
import 'package:chh_app/widgets/comment_mode_bar.dart';
import 'package:chh_app/widgets/net_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

const _avatar =
    'https://www.chiphell.com/data/avatar/000/08/10/01_avatar_small.jpg';

String _comment(String author, {int cid = 1, String body = '合成正文'}) =>
    '<dl id="comment_${cid}_li"><dt>$author'
    '<span class="xg1">2001-01-02 09:30</span></dt><dd>$body</dd></dl>';

ArticleComment _parse(String author, {String body = '合成正文'}) =>
    parseArticleDiscussion(_comment(author, body: body), aid: 1).items.single;

Finder _inside(Finder parent, Finder child) =>
    find.descendant(of: parent, matching: child);

void main() {
  group('合成评论身份解析', () {
    for (final href in [
      'space-uid-81001.html',
      '/space-uid-81001.html',
      'home.php?mod=space&amp;uid=81001',
      'https://www.chiphell.com/home.php?mod=space&amp;uid=81001',
      '//chiphell.com/space-uid-81001.html',
      'home.php?%6dod=space&amp;%75id=81001',
      'home.php?mod=%73pace&amp;uid=%38%31%30%30%31',
      '/%73pace-uid-81001.html',
    ]) {
      test('无 img 的合法作者链接生成已验证形态头像：$href', () {
        final comment = _parse('<a href="$href">合成甲</a>');
        expect(comment.author, '合成甲');
        expect(comment.authorUid, '81001');
        expect(comment.avatarUrl, _avatar);
      });
    }

    test('显式头像优先于 UID 回退，同 UID 的头像与名字链接不冲突', () {
      final comment = _parse('''
<a class="avt" href="space-uid-81001.html"><img src="/data/avatar/synthetic.jpg"></a>
<a href="home.php?mod=space&amp;uid=81001">合成甲</a>''');
      expect(comment.author, '合成甲');
      expect(comment.authorUid, '81001');
      expect(
        comment.avatarUrl,
        'https://www.chiphell.com/data/avatar/synthetic.jpg',
      );
    });

    test('编码与普通作者链接指向相同 UID 时保留身份', () {
      final comment = _parse(
        '<a href="space-uid-81001.html">合成甲</a>'
        '<a href="home.php?%6dod=space&amp;%75id=81001">合成甲</a>',
      );
      expect(comment.authorUid, '81001');
      expect(comment.avatarUrl, _avatar);
    });

    test('编码冲突候选与独立边界探针等价，不挑选第一个身份', () {
      expect(Uri.parse('home.php?%6dod=space&%75id=82002').queryParameters, {
        'mod': 'space',
        'uid': '82002',
      });
      final comment = _parse(
        '<a href="space-uid-82001.html">合成甲</a>'
        '<a href="home.php?%6dod=space&amp;%75id=82002">合成乙</a>',
      );
      expect(comment.authorUid, isNull);
      expect(comment.avatarUrl, isNull);
    });

    for (final href in [
      'home.php?%6dod=space&amp;%75id=0',
      'home.php?%6dod=space&amp;%75id=-1',
      'home.php?%6dod=space&amp;%75id=81002x',
      'home.php?%6dod=space&amp;%75id=081002',
      'home.php?%6dod=space&amp;%75id=1000000001',
      'home.php?%6dod=space&amp;%75id=81001&amp;uid=81002',
      'home.php?%6dod=space&amp;%75id=81001&amp;uid=81001',
      'home.php?%6dod=spacecp&amp;%75id=81002',
      'home.php?%6dod=space&amp;%74ouid=81002',
      'space-uid-81001.html?%75id=81002',
      'https://example.invalid/home.php?%6dod=space&amp;%75id=81002',
      '//www.chiphell.com.example.invalid/home.php?%6dod=space&amp;%75id=81002',
      'https://user@www.chiphell.com/home.php?%6dod=space&amp;%75id=81002',
      'https://www.chiphell.com:8443/home.php?%6dod=space&amp;%75id=81002',
      'javascript:home.php?%6dod=space&amp;%75id=81002',
      '/%73pace-uid-0.html',
    ]) {
      test('编码非法候选单独或混合时均不能认人：$href', () {
        for (final prefix in ['', '<a href="space-uid-81001.html">合成甲</a>']) {
          final comment = _parse('$prefix<a href="$href">合成乙</a>');
          expect(comment.authorUid, isNull, reason: prefix);
          expect(comment.avatarUrl, isNull, reason: prefix);
        }
      });
    }

    for (final href in [
      'space-uid-0.html',
      'space-uid--1.html',
      'space-uid-81001oops.html',
      'space-uid-081001.html',
      'space-uid-1000000001.html',
      'home.php?mod=space&amp;uid=0',
      'home.php?mod=space&amp;uid=81001x',
      'home.php?mod=space&amp;uid=81001&amp;uid=81002',
      'home.php?mod=space&amp;uid=81001&amp;uid=81001',
      'home.php?mod=spacecp&amp;uid=81001',
      'home.php?mod=space&amp;touid=81001',
      'space-uid-81001.html?uid=81002',
      'https://example.invalid/space-uid-81001.html',
      '//www.chiphell.com.example.invalid/space-uid-81001.html',
      'https://www.chiphell.com@elsewhere.invalid/space-uid-81001.html',
      'https://user@www.chiphell.com/space-uid-81001.html',
      'https://www.chiphell.com:8443/space-uid-81001.html',
      'javascript:space-uid-81001.html',
      '/redirect?next=space-uid-81001.html',
      'https://[invalid/space-uid-81001.html',
    ]) {
      test('不从非法或不可信链接猜用户：$href', () {
        final comment = _parse('<a href="$href">合成甲</a>');
        expect(comment.author, '合成甲');
        expect(comment.authorUid, isNull);
        expect(comment.avatarUrl, isNull);
      });
    }

    test('缺 UID 保留姓名，不借正文和引用里的用户或头像', () {
      final comment = _parse(
        '匿名合成作者',
        body:
            '<div class="quote"><blockquote><a href="space-uid-81002.html">'
            '合成乙</a><span class="avt"><img src="/other.jpg"></span>'
            '</blockquote></div>合成正文',
      );
      expect(comment.author, '匿名合成作者');
      expect(comment.authorUid, isNull);
      expect(comment.avatarUrl, isNull);
      expect(comment.text, contains('合成正文'));
    });

    test('作者区域的引用不参与身份解析', () {
      final comment = _parse('''
<div class="quote"><a href="space-uid-81002.html">合成乙</a></div>
<a href="space-uid-81001.html">合成甲</a>''');
      expect(comment.author, '合成甲');
      expect(comment.authorUid, '81001');
      expect(comment.avatarUrl, _avatar);
    });

    for (final other in [
      'space-uid-81002.html',
      'https://example.invalid/space-uid-81002.html',
      'space-uid-0.html',
      'home.php?%6dod=space&amp;%75id=81002',
      '/%73pace-uid-81002.html',
    ]) {
      test('混合作者链接有冲突或不可信候选时不选第一个：$other', () {
        final comment = _parse(
          '<a href="space-uid-81001.html">合成甲</a>'
          '<a href="$other">合成乙</a>',
        );
        expect(comment.authorUid, isNull);
        expect(comment.avatarUrl, isNull);
      });
    }

    test('其他楼层与嵌套评论不能替缺少 dt 的评论认人', () {
      final parsed = parseArticleDiscussion('''
<dl id="comment_1_li"><dd>合成正文
${_comment('<a href="space-uid-81002.html">合成乙</a>', cid: 2)}
</dd></dl>
${_comment('<a href="space-uid-81001.html">合成甲</a>', cid: 3)}
''', aid: 1);
      expect(parsed.items.first.authorUid, isNull);
      expect(parsed.items.first.avatarUrl, isNull);
      expect(parsed.items.last.authorUid, '81001');
    });

    for (final src in [
      '',
      'javascript:alert(1)',
      'https://example.invalid/a.jpg',
    ]) {
      test('无效显式头像不压过可信 UID 回退：$src', () {
        final comment = _parse(
          '<a class="avt" href="space-uid-81001.html">'
          '<img src="$src"></a><a href="space-uid-81001.html">合成甲</a>',
        );
        expect(comment.avatarUrl, _avatar);
      });
    }
  });

  testWidgets('完整 show 弹层中两位作者的头像和名字均进入正确 App 主页，覆盖三模式及楼中楼', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final originalFetchers = List<ChhFetcher>.of(chhClient.fetchers);
    final originalCache = imageDiskCache;
    final transport = _ProfileFetcher();
    chhClient.fetchers
      ..clear()
      ..add(transport);
    chhClient.clearCache();
    imageDiskCache = ImageDiskCache(null);
    imageHttpClientFactory = () => _OfflineImages();
    addTearDown(() {
      chhClient.fetchers
        ..clear()
        ..addAll(originalFetchers);
      chhClient.clearCache();
      imageDiskCache = originalCache;
      imageHttpClientFactory = () => HttpClient();
    });

    final discussion = parseArticleDiscussion(
      _comment('<a href="space-uid-81001.html">合成甲</a>') +
          _comment(
            '<a href="home.php?mod=space&amp;uid=81002">合成乙</a>',
            cid: 2,
            body:
                '<div class="quote"><blockquote>合成甲: 合成正文</blockquote></div>合成回复',
          ) +
          _comment('匿名合成作者', cid: 3),
      aid: 1,
    ).withAuthors(uid: '81001');
    var loads = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(
          Brightness.light,
        ).copyWith(platform: TargetPlatform.android),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => ArticleDiscussionPage.show(
                context,
                aid: 1,
                title: '合成身份测试',
                loadPage: (_, _) async {
                  loads++;
                  return discussion;
                },
                isLoggedIn: () => false,
              ),
              child: const Text('打开合成评论'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开合成评论'));
    await tester.pumpAndSettle();
    expect(transport.requested, isEmpty);

    for (final mode in ['评论', '原楼层', '只看作者']) {
      if (mode != '评论') {
        await tester.tap(_inside(find.byType(CommentModeBar), find.text(mode)));
        await tester.pumpAndSettle();
      } else {
        await tester.tap(
          find.byKey(const ValueKey('article-expand-replies-1')),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<ArticleCommentTile>(
                find.byKey(const ValueKey('comment-2')),
              )
              .nested,
          isTrue,
        );
      }
      for (final cid in mode == '只看作者' ? [1] : [1, 2]) {
        final tile = find.byKey(ValueKey('comment-$cid'));
        final uid = cid == 1 ? '81001' : '81002';
        final name = cid == 1 ? '合成甲' : '合成乙';
        final avatar = _inside(tile, find.byType(ClipOval));
        final nameTarget = _inside(tile, find.text(name));
        final profileLinks = _inside(
          tile,
          find.byWidgetPredicate(
            (widget) =>
                widget is PressScale && widget.semanticLabel == '查看$name的主页',
          ),
        );
        expect(profileLinks, findsNWidgets(2));
        expect(
          tester.getSize(avatar),
          cid == 2 && mode == '评论' ? const Size(24, 24) : const Size(32, 32),
        );
        // 合成传输故意让头像失败，仍显示占位，正文和主页入口不受影响。
        expect(_inside(avatar, find.byIcon(AppIcons.image)), findsOneWidget);
        expect(
          _inside(tile, find.text(cid == 1 ? '合成正文' : '合成回复')),
          findsOneWidget,
        );
        if (cid == 1) expect(_inside(tile, find.text('作者')), findsOneWidget);
        for (final target in [avatar, nameTarget]) {
          await tester.ensureVisible(target);
          await tester.pumpAndSettle();
          await tester.tap(target);
          await tester.pumpAndSettle();
          expect(find.byType(UserDrawer), findsOneWidget);
          expect(tester.widget<UserDrawer>(find.byType(UserDrawer)).uid, uid);
          expect(
            tester.widget<UserProfileBody>(find.byType(UserProfileBody)).uid,
            uid,
          );
          expect(find.text('合成主页$uid'), findsNWidgets(2));
          await tester.tap(
            find.byWidgetPredicate(
              (w) => w is ChromeButton && w.tooltip == '关闭',
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(UserDrawer), findsNothing);
          expect(find.byType(ArticleDiscussionPage), findsOneWidget);
          expect(
            tester.widget<NetImage>(_inside(tile, find.byType(NetImage))).url,
            cid == 1 ? _avatar : _avatar.replaceFirst('/01_', '/02_'),
          );
        }
      }
      if (mode != '只看作者') {
        final anonymous = find.byKey(const ValueKey('comment-3'));
        await tester.tap(_inside(anonymous, find.byType(ClipOval)));
        await tester.tap(_inside(anonymous, find.text('匿名合成作者')));
        await tester.pumpAndSettle();
        expect(find.byType(UserDrawer), findsNothing);
      }
    }
    expect(transport.requested, ['81001', '81002']);
    expect(loads, 1);
    expect(tester.takeException(), isNull);
  });

  for (final uid in <String?>[
    null,
    '',
    '0',
    '-1',
    'abc',
    '81001x',
    '081001',
    '1000000001',
  ]) {
    testWidgets('无有效 UID 的名字和头像均无导航：$uid', (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(Brightness.light),
            home: Scaffold(
              body: ArticleCommentTile(
                comment: ArticleComment(
                  cid: 1,
                  author: '合成匿名',
                  authorUid: uid,
                  text: '正文',
                ),
                onReply: () {},
              ),
            ),
          ),
        );
        final links = tester
            .widgetList<PressScale>(find.byType(PressScale))
            .where((link) => link.semanticLabel?.startsWith('查看') ?? false);
        for (final target in ['author', 'avatar']) {
          final finder = find.byKey(ValueKey('article-comment-$target-1'));
          final data = tester.getSemantics(finder).getSemanticsData();
          expect(data.flagsCollection.isButton, isFalse);
          expect(data.hasAction(SemanticsAction.tap), isFalse);
          expect(data.label, isNot(contains('主页')));
          expect(
            find.ancestor(of: finder, matching: find.byType(PressScale)),
            findsNothing,
          );
        }
        expect(links, isEmpty);
        expect(tester.getSemantics(find.text('合成匿名')).label, contains('合成匿名'));
        await tester.tap(find.text('合成匿名'));
        await tester.tap(find.byType(ClipOval));
        await tester.pumpAndSettle();
        expect(find.byType(UserDrawer), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  }
}

class _ProfileFetcher extends ChhFetcher {
  final requested = <String>[];
  @override
  String get name => 'synthetic-identity';
  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) async {
    final uid = RegExp(
      r'^/space-uid-(81001|81002)\.html$',
    ).firstMatch(url.path)?.group(1);
    expect(uid, isNotNull);
    requested.add(uid!);
    return ChhResponse(200, '<html><h2 class="mbn">合成主页$uid</h2></html>');
  }

  @override
  Future<ChhResponse> postForm(Uri url, Map<String, String> fields) async {
    fail('身份测试不得发送消息');
  }
}

class _OfflineImages implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      throw const SocketException('合成头像加载失败');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
