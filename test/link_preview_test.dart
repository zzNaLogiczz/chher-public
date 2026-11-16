import 'dart:async';
import 'dart:io';

import 'package:chh_app/core/link_target.dart';
import 'package:chh_app/data/link_preview_repository.dart';
import 'package:chh_app/data/portal_repository.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/parser/archiver_parser.dart';
import 'package:flutter_test/flutter_test.dart';

final _archiver = File('test_data/archiver_synthetic.html').readAsStringSync();

ThreadLink _thread(int tid) =>
    classifyLink('thread-$tid-1-1.html')! as ThreadLink;

ArticleDetail _article(String title, String? meta) => ArticleDetail(
  aid: 1,
  title: title,
  metaRaw: meta,
  content: const [],
  page: const PageInfo(current: 1, hasNext: false),
);

class _Fetcher extends ChhFetcher {
  @override
  final String name;
  final ChhResponse response;
  final calls = <Uri>[];
  _Fetcher(this.name, this.response);

  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) async {
    calls.add(url);
    return response;
  }
}

void main() {
  group('只走直连', () {
    late _Fetcher direct;
    late _Fetcher webview;
    late LinkPreviewRepository repo;

    setUp(() {
      direct = _Fetcher('direct', const ChhResponse(567, 'blocked'));
      webview = _Fetcher('webview', ChhResponse(200, _archiver));
      final client = ChhClient(fetchers: [direct, webview]);
      repo = LinkPreviewRepository.live(client, PortalRepository(client));
    });

    test('帖子预览被拦就算失败，不降级到 WebView 和正文抢通道', () async {
      expect(await repo.preview(_thread(1)), isNull);
      expect(direct.calls, hasLength(1));
      expect(webview.calls, isEmpty);
    });

    test('文章预览同样不降级', () async {
      expect(await repo.preview(classifyLink('article-50001-1.html')!), isNull);
      expect(webview.calls, isEmpty);
    });
  });

  group('Archiver 解析', () {
    test('取标题与发表时间', () {
      final meta = parseArchiverThread(_archiver)!;
      expect(meta.title, '[ITX] 合成装机记录');
      expect(meta.time, DateTime(2026, 1, 2, 3, 4));
      expect(meta.author, '示例作者甲');
      expect(meta.excerpt, '用于链接预览的合成内容。');
    });

    test('摘要支持裸文本和换行，不混入下一位作者', () {
      final meta = parseArchiverThread(
        '<div id="content"><h3>标题</h3><br> 首段 <b>纯文本</b><br>第二段<p class="author"><strong>回帖作者</strong></p>回复</div>',
      )!;
      expect(meta.author, isNull);
      expect(meta.excerpt, '首段 纯文本');
      expect(
        parseArchiverThread(
          '<div id="content"><h3>标题</h3><p class="author">回帖作者</p><p>回复</p></div>',
        )!.excerpt,
        isNull,
      );
    });

    test('摘要不包含嵌入脚本与样式，段内换行保留空格', () {
      final meta = parseArchiverThread(
        '<div id="content"><h3>标题</h3><p>开头<script>隐藏脚本</script><style>隐藏样式</style><br>后续</p></div>',
      )!;
      expect(meta.excerpt, '开头 后续');
    });

    test('摘要跳过独立或嵌套的 pstatus，读取后面的正文', () {
      const edited = '本帖最后由 合成作者 于 2026-11-15 01:21 编辑';
      for (final body in [
        '<i class="pstatus">$edited</i><br><br><p>真正的正文</p>',
        '<p><i class="pstatus">$edited</i></p><p>真正的正文</p>',
        '<div><i class="pstatus">$edited</i><br>真正的正文</div>',
      ]) {
        final meta = parseArchiverThread(
          '<div id="content"><h3>标题</h3>$body<p>第二段</p></div>',
        )!;
        expect(meta.excerpt, '真正的正文', reason: body);
      }
    });

    test('摘要跳过纯文本编辑段落和换行分隔的编辑说明', () {
      const edited = '本帖最后由 合成作者 于 2026-11-15 01:21 编辑';
      for (final body in [
        '<p>$edited</p><p>真正的正文</p>',
        '<div><p>$edited</p><p>真正的正文</p></div>',
        '<p>$edited<br>真正的正文</p>',
        '<div>$edited<br><br>真正的正文</div>',
        '$edited<br><br>真正的正文<br>第二段',
        '本帖最后由 <b>合成作者</b> 于 2026-11-15 01:21 编辑<br>真正的正文',
        '$edited<p>真正的正文</p>',
      ]) {
        final meta = parseArchiverThread(
          '<div id="content"><h3>标题</h3>$body</div>',
        )!;
        expect(meta.excerpt, '真正的正文', reason: body);
      }
    });

    test('只有编辑说明时摘要为空，不把回帖当作正文', () {
      const edited = '本帖最后由 合成作者 于 2026-11-15 01:21 编辑';
      for (final body in [
        '<i class="pstatus">$edited</i><br>',
        '<p>$edited</p>',
        edited,
      ]) {
        for (final reply in ['', '<p class="author">回帖作者</p><p>回帖正文</p>']) {
          expect(
            parseArchiverThread(
              '<div id="content"><h3>标题</h3>$body$reply</div>',
            )!.excerpt,
            isNull,
            reason: '$body$reply',
          );
        }
      }
    });

    test('嵌套容器跳过编辑说明后只取第一段正文', () {
      const edited = '本帖最后由 合成作者 于 2026-11-15 01:21 编辑';
      for (final body in [
        '<div><p>$edited</p><p>真正第一段</p><p>第二段</p></div>',
        '<div><i class="pstatus">$edited</i><p>真正第一段</p><p>第二段</p></div>',
        '<div>$edited<br><div><p>真正第一段</p><p>第二段</p></div></div>',
      ]) {
        expect(
          parseArchiverThread(
            '<div id="content"><h3>标题</h3>$body</div>',
          )!.excerpt,
          '真正第一段',
          reason: body,
        );
      }
    });

    test('正文提及编辑说明时不误删普通文字', () {
      const body = '说明：本帖最后由 合成作者 于 2026-11-15 01:21 编辑';
      for (final html in [
        '<p>$body</p>',
        '<p>说明：<span>本帖最后由 合成作者 于 2026-11-15 01:21 编辑</span></p>',
      ]) {
        expect(
          parseArchiverThread(
            '<div id="content"><h3>标题</h3>$html</div>',
          )!.excerpt,
          body,
        );
      }
    });

    test('编辑说明和图片网址之后继续找首段正文', () {
      const edited = '本帖最后由 合成作者 于 2026-11-15 01:21 编辑';
      const image = 'https://static.chiphell.com/forum/202609/27/sample.jpg';
      for (final body in [
        '<p>$edited</p><p>$image</p><p>真正的正文</p>',
        '$edited<br>$image<br>真正的正文<br>第二段',
        '<div><p>$edited</p><p><a href="$image">$image</a></p>'
            '<p>真正的正文</p></div>',
        '<p>$edited<br>$image<br>真正的正文</p>',
        '<p>$edited\n$image\n真正的正文</p>',
      ]) {
        expect(
          parseArchiverThread(
            '<div id="content"><h3>标题</h3>$body<p>第二段</p></div>',
          )!.excerpt,
          '真正的正文',
          reason: body,
        );
      }
    });

    test('跳过各种纯网址、图片路径和空白段落', () {
      for (final url in [
        for (final extension in ['jpg', 'jpeg', 'png', 'gif', 'webp', 'JPG'])
          'https://example.test/image.$extension?size=1&amp;zoom=2#image',
        'http://example.test/page',
        'https://static.chiphell.com/forum/attachment-without-extension',
        '//static.chiphell.com/forum/image.jpg',
        'static.chiphell.com/forum/image.jpg',
        'attachment.php?aid=123',
        '/forum/attachment.php?aid=123',
        'forum.php?mod=attachment&amp;aid=123',
        'images/sample.webp',
      ]) {
        expect(
          parseArchiverThread(
            '<div id="content"><h3>标题</h3><p>&nbsp;</p>'
            '<p>$url</p><p><br></p><p>真正的正文</p></div>',
          )!.excerpt,
          '真正的正文',
          reason: url,
        );
      }
    });

    test('只有图片或网址时没有摘要且不借用回帖', () {
      for (final body in [
        '<img src="https://example.test/image.jpg" alt="图片说明">',
        '<p>https://example.test/image.jpg</p>',
        '<p><a href="attachment.php?aid=123">attachment.php?aid=123</a></p>',
        '<div><p><img src="https://example.test/image.png"></p></div>',
        '<p>（https://example.test/image.gif）</p><p>，。！？</p>',
        '<p>&nbsp;</p><br>',
      ]) {
        for (final reply in ['', '<p class="author">回帖作者</p><p>回帖正文</p>']) {
          expect(
            parseArchiverThread(
              '<div id="content"><h3>标题</h3>$body$reply</div>',
            )!.excerpt,
            isNull,
            reason: '$body$reply',
          );
        }
      }
    });

    test('段内网址去掉后保留前后文字和描述性链接文字', () {
      for (final (body, expected) in [
        ('前文 https://example.test/image.jpg 后文', '前文 后文'),
        ('前文https://example.test/image.jpg，后文。', '前文，后文。'),
        ('前文http://example.test/page后文', '前文后文'),
        ('前文 attachment.php?aid=123 后文', '前文 后文'),
        ('前文 <a href="https://example.test">参考说明</a> 后文', '前文 参考说明 后文'),
        (
          '前文 <a href="https://example.test">https://example.test</a> 后文',
          '前文 后文',
        ),
      ]) {
        expect(
          parseArchiverThread(
            '<div id="content"><h3>标题</h3><p>$body</p><p>第二段</p></div>',
          )!.excerpt,
          expected,
          reason: body,
        );
      }
    });

    test('附件占位说明不作为摘要，继续找正文', () {
      for (final body in [
        '<p>下载附件</p><p>保存到相册</p><p>上传</p>',
        '<p>下载附件 (120 KB, 下载次数: 3)</p>',
        '<p><a href="attachment.php?aid=123">下载附件</a> '
            '<a href="#">保存到相册</a></p>',
        '<p>下载附件<br>保存到相册<br>上传</p>',
        '下载附件<br>保存到相册<br>2026-11-15 01:21 上传<br>',
        '<div class="aimg_tip"><p>sample.jpg (120 KB)</p>'
            '<p>下载附件</p><p>2026-11-15 01:21 上传</p></div>',
      ]) {
        expect(
          parseArchiverThread(
            '<div id="content"><h3>标题</h3>$body<p>真正的正文</p></div>',
          )!.excerpt,
          '真正的正文',
          reason: body,
        );
        expect(
          parseArchiverThread(
            '<div id="content"><h3>标题</h3>$body'
            '<p class="author">回帖作者</p><p>回帖正文</p></div>',
          )!.excerpt,
          isNull,
          reason: body,
        );
      }
    });

    test('正文讨论上传或下载附件时保留整句', () {
      const body = '上传完成后，可以下载附件并保存到相册。';
      expect(
        parseArchiverThread(
          '<div id="content"><h3>标题</h3><p>$body</p></div>',
        )!.excerpt,
        body,
      );
    });

    test('网址过滤在80字截取之前完成', () {
      final body = '正文😀' * 30;
      expect(
        parseArchiverThread(
          '<div id="content"><h3>标题</h3>'
          '<p>https://example.test/${'a' * 100}.jpg $body</p></div>',
        )!.excerpt,
        String.fromCharCodes(body.runes.take(80)),
      );
    });

    test('摘要限制80个字符并保留Unicode字符', () {
      final meta = parseArchiverThread(
        '<div id="content"><h3>标题</h3><p>${'图😀' * 90}</p></div>',
      )!;
      expect(meta.excerpt!.runes.length, 80);
      expect(meta.excerpt, '图😀' * 40);
      expect(meta.author, isNull);
    });

    test('没有帖子内容的页面返回 null', () {
      expect(parseArchiverThread('<html><body>无权访问</body></html>'), isNull);
    });
  });

  group('LinkPreviewRepository', () {
    late List<Uri> fetched;
    late Map<String, Completer<String>> pending;
    late DateTime now;
    late LinkPreviewRepository repo;

    setUp(() {
      fetched = [];
      pending = {};
      now = DateTime(2026, 10, 28, 12);
      repo = LinkPreviewRepository(
        fetchHtml: (uri) {
          fetched.add(uri);
          return (pending[uri.toString()] = Completer<String>()).future;
        },
        openArticle: (aid) async =>
            ArticleContent(_article('秋季散热器横评', '2026-9-30 10:00| 发布者: x')),
        now: () => now,
      );
    });

    test('帖子读取 Archiver 页而不是整页', () async {
      final future = repo.preview(_thread(900001));
      await Future<void>.delayed(Duration.zero);
      expect(fetched.single.toString(), contains('archiver'));
      pending.values.single.complete(_archiver);
      final p = (await future)!;
      expect(p.title, startsWith('[ITX]'));
      expect(p.time, DateTime(2026, 1, 2, 3, 4));
      expect(p.isThread, isTrue);
      expect(p.author, '示例作者甲');
      expect(p.excerpt, '用于链接预览的合成内容。');
    });

    test('同时最多 2 个请求，其余排队', () async {
      final futures = [for (var i = 1; i <= 5; i++) repo.preview(_thread(i))];
      await Future<void>.delayed(Duration.zero);
      expect(fetched, hasLength(2));
      pending.values.first.complete(_archiver);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(fetched, hasLength(3));
      for (final c in pending.values) {
        if (!c.isCompleted) c.complete(_archiver);
      }
      await Future<void>.delayed(Duration.zero);
      for (final c in pending.values) {
        if (!c.isCompleted) c.complete(_archiver);
      }
      await Future.wait(futures);
      expect(fetched, hasLength(5));
    });

    test('同一目标并发和重复请求只读一次，结果走缓存', () async {
      final a = repo.preview(_thread(7));
      final b = repo.preview(_thread(7));
      await Future<void>.delayed(Duration.zero);
      pending.values.single.complete(_archiver);
      expect((await a)!.title, (await b)!.title);
      expect(repo.cached(_thread(7))!.title, startsWith('[ITX]'));
      await repo.preview(_thread(7));
      expect(fetched, hasLength(1));
    });

    test('失败结果缓存 5 分钟，之后再试', () async {
      final first = repo.preview(_thread(8));
      await Future<void>.delayed(Duration.zero);
      pending.values.single.completeError(StateError('登录墙'));
      expect(await first, isNull);
      expect(repo.hasFailed(_thread(8)), isTrue);

      expect(await repo.preview(_thread(8)), isNull);
      expect(fetched, hasLength(1));

      now = now.add(const Duration(minutes: 5, seconds: 1));
      final retry = repo.preview(_thread(8));
      await Future<void>.delayed(Duration.zero);
      expect(fetched, hasLength(2));
      pending.values.last.complete(_archiver);
      expect(await retry, isNotNull);
    });

    test('页面结构不对算失败', () async {
      final f = repo.preview(_thread(9));
      await Future<void>.delayed(Duration.zero);
      pending.values.single.complete('<html><body>抱歉，帖子不存在</body></html>');
      expect(await f, isNull);
    });

    test('文章读取标题与 meta 里的日期', () async {
      final p = (await repo.preview(classifyLink('article-50001-1.html')!))!;
      expect(p.title, '秋季散热器横评');
      expect(p.time, DateTime(2026, 9, 30, 10));
      expect(p.isThread, isFalse);
    });

    test('文章首图复用openArticle响应且不新增请求', () async {
      var calls = 0;
      final r = LinkPreviewRepository(
        fetchHtml: (_) async => throw StateError('不应新增请求'),
        openArticle: (_) async {
          calls++;
          return ArticleContent(
            ArticleDetail(
              aid: 1,
              title: '合成文章',
              content: const [
                TextBlock('正文'),
                ImageBlock('https://example.test/first.jpg'),
                ImageBlock('https://example.test/second.jpg'),
              ],
              page: const PageInfo(current: 1, hasNext: false),
            ),
          );
        },
      );
      final target = classifyLink('article-1-1.html')!;
      expect(
        (await r.preview(target))!.coverUrl,
        'https://example.test/first.jpg',
      );
      await r.preview(target);
      expect(calls, 1);
    });

    test('文章其实是论坛帖时类型改为帖子', () async {
      final r = LinkPreviewRepository(
        fetchHtml: (_) async => _archiver,
        openArticle: (_) async => const ThreadContent(900001, '其实是帖子'),
        now: () => now,
      );
      final p = (await r.preview(classifyLink('article-50002-1.html')!))!;
      expect(p.title, '其实是帖子');
      expect(p.isThread, isTrue);
    });

    test('缓存最多保留 200 个，最久没用的先淘汰', () async {
      final r = LinkPreviewRepository(
        fetchHtml: (_) async => _archiver,
        openArticle: (_) async => throw UnimplementedError(),
        now: () => now,
      );
      for (var i = 1; i <= 201; i++) {
        await r.preview(_thread(i));
      }
      expect(r.cached(_thread(1)), isNull);
      expect(r.cached(_thread(201)), isNotNull);
    });
  });
}
