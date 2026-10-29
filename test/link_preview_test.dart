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
