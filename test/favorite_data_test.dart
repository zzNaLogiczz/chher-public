/// 全部请求由本地 fake 通道处理,不接触真实论坛。
library;

import 'dart:async';
import 'dart:io';

import 'package:chh_app/data/favorite_repository.dart';
import 'package:chh_app/models/models.dart' show PageMessage;
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:chh_app/parser/favorite_parser.dart';
import 'package:chh_app/parser/space_parser.dart';
import 'package:flutter_test/flutter_test.dart';

const _thread = FavoriteTarget(
  type: FavoriteType.thread,
  targetId: 42,
  title: '帖子标题',
);
const _forum = FavoriteTarget(
  type: FavoriteType.forum,
  targetId: 80,
  title: '电脑讨论',
);
String _message(String text) => '<div id="messagetext">$text</div>';
String _form({bool deleting = false, String type = 'thread', int id = 42}) =>
    '''
<form id="favoriteform_$id" method="post"
 action="home.php?mod=spacecp&amp;ac=favorite&amp;${deleting ? 'op=delete&amp;favid=2001&amp;type=all' : 'type=$type&amp;id=$id&amp;spaceuid=0'}">
<input type="hidden" name="referer" value="https://www.chiphell.com/">
<input type="hidden" name="formhash" value="fresh-hash">
<input type="hidden" name="${deleting ? 'deletesubmit' : 'favoritesubmit'}" value="true">
<input type="hidden" name="server_token" value="keep&amp;me">
<textarea name="description">旧描述</textarea></form>''';
String _item({
  String favid = '2001',
  String type = 'thread',
  int id = 42,
  String? url,
  bool metadata = true,
  String? vid,
}) =>
    '''
<li id="fav_$favid"><a id="a_delete_$favid" href="home.php?ac=favorite&amp;op=delete">删除</a>
${metadata ? '<input name="favorite[]" value="$favid" vid="${vid ?? id}"><span><img class="t" alt="$type"></span>' : ''}
<a href="${url ?? (type == 'thread'
            ? 'thread-$id-1-1.html'
            : type == 'forum'
            ? 'forum-$id-1.html'
            : 'article-$id-1.html')}">标题$id</a><span class="xg1">2026-10-30</span></li>''';
String _list(String items, {String? next}) =>
    '<ul id="favorite_ul">$items</ul>${next == null ? '' : '<div class="pg"><strong>1</strong><a class="nxt" href="$next">下一页</a></div>'}';
FavoriteItem _entry(
  FavoriteTarget target, {
  String favid = '2001',
}) => FavoriteItem(
  type: target.type,
  targetId: target.targetId,
  favid: favid,
  title: target.title,
  url: 'https://www.chiphell.com/${target.type.name}-${target.targetId}-1.html',
);

class _Transport extends ChhFetcher {
  FutureOr<String> Function(Uri) get;
  String response = _message('收藏成功');
  int status = 200;
  final gets = <Uri>[];
  final posts = <({Uri url, Map<String, String> fields})>[];
  _Transport(this.get);
  @override
  String get name => 'favorite-fake';
  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) async {
    gets.add(url);
    return ChhResponse(200, await get(url));
  }

  @override
  Future<ChhResponse> postForm(Uri url, Map<String, String> form) async {
    posts.add((url: url, fields: Map.of(form)));
    return ChhResponse(status, response);
  }
}

class _Client extends ChhClient {
  final refreshes = <bool>[];
  _Client(_Transport transport) : super(fetchers: [transport]);
  @override
  Future<String> getHtml(
    Uri url, {
    bool refresh = false,
    bool fallback = true,
  }) {
    refreshes.add(refresh);
    return super.getHtml(url, refresh: refresh, fallback: fallback);
  }
}

void main() {
  group('收藏解析', () {
    test('列表读取类型、vid、favid,不误取删除标题', () {
      final parsed = parseFavorites(
        _list(
          [
            _item(),
            _item(type: 'forum', id: 80, favid: '2002'),
            _item(type: 'article', id: 90, favid: '2003'),
          ].join(),
        ),
      );
      expect(parsed.items.map((e) => e.type), [
        FavoriteType.thread,
        FavoriteType.forum,
        FavoriteType.article,
      ]);
      expect(parsed.items.map((e) => e.targetId), [42, 80, 90]);
      expect(parsed.items.map((e) => e.favid), ['2001', '2002', '2003']);
      expect(parsed.items.first.title, '标题42');
      expect(parsed.items[1].fid, 80);
    });
    test('类型与vid优先于URL,无效元数据按URL回退', () {
      final first = parseFavorites(
        _list(_item(type: 'forum', id: 80, url: 'thread-42-1-1.html')),
      ).items.single;
      expect(first.type, FavoriteType.forum);
      expect(first.targetId, 80);
      final fallback = parseFavorites(
        _list(
          _item(
            type: 'unknown',
            id: 90,
            vid: 'bad',
            url: 'portal.php?mod=view&amp;aid=90',
          ),
        ),
      ).items.single;
      expect(fallback.type, FavoriteType.article);
      expect(fallback.targetId, 90);
    });
    test('旧样例缺元数据时仍识别三种URL及查询aid', () {
      for (final type in ['thread', 'forum', 'article']) {
        final item = parseFavorites(
          _list(_item(type: type, id: 99, metadata: false)),
        ).items.single;
        expect(item.type.name, type);
        expect(item.targetId, 99);
      }
      expect(
        parseFavorites(
          _list(_item(metadata: false, url: 'portal.php?mod=view&amp;aid=123')),
        ).items.single.targetId,
        123,
      );
    });
    test('收藏和删除表单保留action与全部hidden字段', () {
      for (final deleting in [false, true]) {
        final parsed = parseFavoriteForm(_form(deleting: deleting))!;
        expect(parsed.action.host, 'www.chiphell.com');
        expect(parsed.action.queryParameters['ac'], 'favorite');
        expect(
          parsed.action.queryParameters[deleting ? 'favid' : 'id'],
          deleting ? '2001' : '42',
        );
        expect(parsed.hidden, {
          'referer': 'https://www.chiphell.com/',
          'formhash': 'fresh-hash',
          deleting ? 'deletesubmit' : 'favoritesubmit': 'true',
          'server_token': 'keep&me',
        });
      }
    });
    test('识别已收藏消息,登录和错误消息不误判', () {
      expect(isAlreadyFavorited(_message('抱歉，您已收藏，请勿重复收藏')), isTrue);
      expect(isAlreadyFavorited(_message('请先登录才能查看已收藏')), isFalse);
      expect(isAlreadyFavorited(_message('收藏失败')), isFalse);
      expect(parseFavoriteForm(_message('不存在')), isNull);
    });
  });

  group('收藏索引', () {
    test('持久化往返保留uid、顺序和同步时间', () async {
      final dir = await Directory.systemTemp.createTemp('favorite-index-');
      final file = File('${dir.path}/index-v1.json');
      final index = FavoriteIndex(file)..setUid(7);
      await index.load();
      final syncedAt = DateTime(2026, 10, 30);
      index.replace([
        _entry(_thread),
        _entry(_forum, favid: '2002'),
      ], syncedAt: syncedAt);
      await index.flush();
      final restored = FavoriteIndex(file)..setUid(7);
      await restored.load();
      expect(restored.uid, 7);
      expect(restored.items.map((e) => e.targetId), [42, 80]);
      expect(restored.lastSyncedAt, syncedAt);
      expect(restored.entryFor(_forum)?.favid, '2002');
      await restored.flush();
      index.dispose();
      restored.dispose();
      await dir.delete(recursive: true);
    });
    test('启动uid晚到仍可恢复同账号磁盘', () async {
      final dir = await Directory.systemTemp.createTemp('favorite-late-uid-');
      final file = File('${dir.path}/index-v1.json');
      final old = FavoriteIndex(file)
        ..setUid(7)
        ..merge([_entry(_thread)]);
      await old.flush();
      old.dispose();
      final current = FavoriteIndex(null);
      await current.attach(file);
      expect(current.items, isEmpty);
      current.setUid(7);
      await current.load();
      expect(current.contains(_thread), isTrue);
      await current.flush();
      current.dispose();
      await dir.delete(recursive: true);
    });
    test('目录就绪前的整体替换不复活磁盘旧条目', () async {
      final dir = await Directory.systemTemp.createTemp('favorite-replace-');
      final file = File('${dir.path}/index-v1.json');
      final old = FavoriteIndex(file)
        ..setUid(7)
        ..merge([_entry(_thread)]);
      await old.flush();
      old.dispose();
      final current = FavoriteIndex(null)
        ..setUid(7)
        ..replace([_entry(_forum)]);
      await current.attach(file);
      expect(current.items.single.targetId, 80);
      await current.flush();
      current.dispose();
      await dir.delete(recursive: true);
    });
    test('uid变化与退出均清空,不同账号不加载旧收藏', () async {
      final index = FavoriteIndex(null)
        ..setUid(7)
        ..merge([_entry(_thread)]);
      index.setUid(8);
      expect(index.items, isEmpty);
      expect(index.lastSyncedAt, isNull);
      index.merge([_entry(_forum)]);
      index.setUid(null);
      expect(index.items, isEmpty);
      index.merge([_entry(_thread)]);
      expect(index.items, isEmpty);
      index.dispose();
    });
    test('同步替换清理旧项,页面并入保留其他条目和顺序', () {
      final index = FavoriteIndex(null)..setUid(7);
      index.replace([_entry(_thread)]);
      index.merge([_entry(_forum)]);
      expect(index.items.map((e) => e.targetId), [42, 80]);
      index.merge([_entry(_thread, favid: 'updated')]);
      expect(index.items.map((e) => e.targetId), [42, 80]);
      expect(index.entryFor(_thread)?.favid, 'updated');
      index.replace([_entry(_forum)]);
      expect(index.contains(_thread), isFalse);
      index.dispose();
    });
    test('首页并入时新条目在最前,后续页不重排已知条目', () {
      final index = FavoriteIndex(null)
        ..setUid(7)
        ..merge([_entry(_thread)]);
      index.merge([_entry(_forum), _entry(_thread)], prepend: true);
      expect(index.items.map((e) => e.targetId), [80, 42]);
      index.merge([_entry(_thread)]);
      expect(index.items.map((e) => e.targetId), [80, 42]);
      index.dispose();
    });
    test('新收藏排在最前,删除立即移除', () {
      final index = FavoriteIndex(null)
        ..setUid(7)
        ..merge([_entry(_thread)]);
      index.put(_forum);
      expect(index.items.map((e) => e.targetId), [80, 42]);
      index.remove(_forum);
      expect(index.contains(_forum), isFalse);
      index.dispose();
    });
  });

  group('收藏仓库', () {
    late FavoriteIndex index;
    late _Transport transport;
    late _Client client;
    late FavoriteRepository repo;
    setUp(() {
      index = FavoriteIndex(null)..setUid(7);
      transport = _Transport(
        (url) =>
            url.queryParameters['do'] == 'favorite' ? _list(_item()) : _form(),
      );
      client = _Client(transport);
      repo = FavoriteRepository(client, index);
    });
    tearDown(() => index.dispose());
    for (final type in [
      FavoriteType.thread,
      FavoriteType.forum,
      FavoriteType.article,
    ]) {
      test('add ${type.name}提交站点action与完整字段', () async {
        transport.get = (url) => url.queryParameters['do'] == 'favorite'
            ? _list(_item(type: type.name))
            : _form(type: type.name);
        expect(
          (await repo.add(
            FavoriteTarget(type: type, targetId: 42, title: '收藏'),
          )).favorited,
          isTrue,
        );
        final post = transport.posts.single;
        expect(post.url.queryParameters, {
          'mod': 'spacecp',
          'ac': 'favorite',
          'type': type.name,
          'id': '42',
          'spaceuid': '0',
        });
        expect(post.fields, {
          'referer': 'https://www.chiphell.com/',
          'formhash': 'fresh-hash',
          'favoritesubmit': 'true',
          'server_token': 'keep&me',
          'description': '',
          'favoritesubmit_btn': 'true',
        });
        expect(
          transport.gets.first.queryParameters.containsKey('formhash'),
          isFalse,
        );
        await repo.sync(firstPageOnly: true);
        expect(client.refreshes.every((e) => e), isTrue);
      });
    }
    test('add已收藏不提交,后台同步取得favid', () async {
      transport.get = (url) => url.queryParameters['do'] == 'favorite'
          ? _list(_item())
          : _message('抱歉，您已收藏，请勿重复收藏');
      expect((await repo.add(_thread)).favorited, isTrue);
      expect(transport.posts, isEmpty);
      await repo.sync();
      expect(index.entryFor(_thread)?.favid, '2001');
    });
    test('add提交返回已收藏消息仍成功,写入索引并后台同步', () async {
      final synchronized = Completer<String>();
      transport.response = _message('抱歉，您已收藏，请勿重复收藏');
      transport.get = (url) => url.queryParameters['do'] == 'favorite'
          ? synchronized.future
          : _form();
      expect((await repo.add(_thread)).favorited, isTrue);
      expect(index.contains(_thread), isTrue);
      expect(index.entryFor(_thread)?.favid, '');
      await Future<void>.delayed(Duration.zero);
      expect(transport.posts, hasLength(1));
      expect(
        transport.gets.where((url) => url.queryParameters['ac'] == 'favorite'),
        hasLength(1),
      );
      expect(transport.gets.last.queryParameters['do'], 'favorite');
      synchronized.complete(_list(_item()));
      await Future<void>.delayed(Duration.zero);
      expect(index.entryFor(_thread)?.favid, '2001');
    });
    for (final status in [200, 302]) {
      test('add无提示响应$status后复核已收藏即成功', () async {
        transport
          ..status = status
          ..response = status == 302 ? '' : '<html><body>首页</body></html>';
        transport.get = (url) {
          if (url.queryParameters['do'] == 'favorite') return _list(_item());
          return transport.posts.isEmpty ? _form() : _message('抱歉，您已收藏，请勿重复收藏');
        };
        expect((await repo.add(_thread)).favorited, isTrue);
        expect(index.contains(_thread), isTrue);
        final probes = transport.gets
            .where((url) => url.queryParameters['ac'] == 'favorite')
            .toList();
        expect(probes, hasLength(2));
        expect(probes.first, probes.last);
        expect(probes.last.queryParameters.containsKey('formhash'), isFalse);
        expect(transport.posts, hasLength(1));
        expect(client.refreshes.every((refresh) => refresh), isTrue);
      });
    }
    test('add无提示响应后仍返回未收藏表单则失败', () async {
      transport.response = '<html><body>首页</body></html>';
      await expectLater(repo.add(_thread), throwsA(isA<StateError>()));
      expect(index.contains(_thread), isFalse);
      expect(transport.gets, hasLength(2));
      expect(transport.posts, hasLength(1));
    });
    test('add明确错误消息直接失败,不再复核', () async {
      transport.response =
          '<div id="messagetext" class="alert_error">收藏失败，请稍后重试</div>';
      await expectLater(
        repo.add(_thread),
        throwsA(
          isA<PageMessage>().having(
            (message) => message.text,
            'text',
            '收藏失败，请稍后重试',
          ),
        ),
      );
      expect(index.contains(_thread), isFalse);
      expect(transport.gets, hasLength(1));
    });
    test('remove有favid提交删除表单并移除索引', () async {
      index.merge([_entry(_thread)]);
      transport.get = (_) => _form(deleting: true);
      transport.response = _message('删除成功');
      expect((await repo.remove(_thread)).favorited, isFalse);
      expect(index.contains(_thread), isFalse);
      expect(transport.posts.single.url.queryParameters['favid'], '2001');
      expect(transport.posts.single.fields, {
        'referer': 'https://www.chiphell.com/',
        'formhash': 'fresh-hash',
        'deletesubmit': 'true',
        'server_token': 'keep&me',
        'deletesubmitbtn': 'true',
      });
      expect(client.refreshes, [true]);
    });
    for (final verified in [
      _message('抱歉，您指定的收藏不存在'),
      '<html><body>收藏列表</body></html>',
    ]) {
      test('remove无提示响应后复核已无删除表单即成功:$verified', () async {
        index.merge([_entry(_thread)]);
        transport.response = '<html><body>首页</body></html>';
        transport.get = (_) =>
            transport.posts.isEmpty ? _form(deleting: true) : verified;
        expect((await repo.remove(_thread)).favorited, isFalse);
        expect(index.contains(_thread), isFalse);
        expect(transport.posts, hasLength(1));
        expect(transport.gets, hasLength(2));
        expect(transport.gets.first, transport.gets.last);
        expect(transport.gets.last.queryParameters, {
          'mod': 'spacecp',
          'ac': 'favorite',
          'op': 'delete',
          'favid': '2001',
        });
        expect(client.refreshes, [true, true]);
      });
    }
    test('remove无提示响应后仍返回删除表单则失败', () async {
      index.merge([_entry(_thread)]);
      transport.get = (_) => _form(deleting: true);
      transport.response = '<html><body>首页</body></html>';
      await expectLater(repo.remove(_thread), throwsA(isA<StateError>()));
      expect(index.contains(_thread), isTrue);
      expect(transport.gets, hasLength(2));
      expect(transport.posts, hasLength(1));
    });
    test('remove复核的权限错误不能当作删除表单消失', () async {
      index.merge([_entry(_thread)]);
      transport.response = '<html><body>首页</body></html>';
      transport.get = (_) =>
          transport.posts.isEmpty ? _form(deleting: true) : _message('没有权限');
      await expectLater(
        repo.remove(_thread),
        throwsA(
          isA<PageMessage>().having((message) => message.text, 'text', '没有权限'),
        ),
      );
      expect(index.contains(_thread), isTrue);
      expect(transport.gets, hasLength(2));
    });
    test('remove没有favid先同步再提交删除', () async {
      index.put(_thread);
      transport.get = (url) => url.queryParameters['do'] == 'favorite'
          ? _list(_item())
          : _form(deleting: true);
      transport.response = _message('操作成功');
      expect((await repo.remove(_thread)).favorited, isFalse);
      expect(transport.gets.first.queryParameters['do'], 'favorite');
      expect(transport.gets.last.queryParameters['op'], 'delete');
      expect(transport.posts, hasLength(1));
      expect(index.items, isEmpty);
    });
    test('remove同步后仍没有目标视为已取消', () async {
      transport.get = (_) => _list('');
      expect((await repo.remove(_thread)).favorited, isFalse);
      expect(transport.posts, isEmpty);
    });
    test('remove遇收藏不存在视为已取消', () async {
      index.merge([_entry(_thread)]);
      transport.get = (_) => _message('抱歉，您指定的收藏不存在');
      expect((await repo.remove(_thread)).favorited, isFalse);
      expect(index.contains(_thread), isFalse);
      expect(transport.posts, isEmpty);
    });
    test('失败提交保留原索引,不会误报取消成功', () async {
      index.merge([_entry(_thread)]);
      transport.get = (_) => _form(deleting: true);
      transport.response = _message('没有权限');
      await expectLater(repo.remove(_thread), throwsA(anything));
      expect(index.contains(_thread), isTrue);
      expect(transport.gets, hasLength(1));
    });
    test('同步失败静默保留旧索引,remove不能假装同步成功', () async {
      index.merge([_entry(_forum)]);
      transport.get = (_) => _message('请先登录');
      await repo.sync();
      expect(index.contains(_forum), isTrue);
      await expectLater(repo.remove(_thread), throwsA(anything));
    });
    test('同步顺序沿用nextUrl并替换全部旧项', () async {
      index.merge([_entry(_forum)]);
      transport.get = (url) => url.queryParameters['page'] == '2'
          ? _list(_item(type: 'article', id: 90, favid: '2003'))
          : _list(
              _item(),
              next:
                  'home.php?mod=space&amp;do=favorite&amp;type=all&amp;page=2&amp;uid=7',
            );
      await repo.sync();
      expect(transport.gets.map((e) => e.queryParameters['page']), ['1', '2']);
      expect(transport.gets.last.queryParameters['uid'], '7');
      expect(index.items.map((e) => e.targetId), [42, 90]);
      expect(index.lastSyncedAt, isNotNull);
    });
    test('只同步第一页并入索引,不删其他页条目', () async {
      index.merge([_entry(_forum)]);
      await repo.sync(firstPageOnly: true);
      expect(index.contains(_forum), isTrue);
      expect(index.contains(_thread), isTrue);
      expect(index.lastSyncedAt, isNull);
    });
    test('同步超过50页保留已有索引', () async {
      index.merge([_entry(_forum)]);
      transport.get = (url) => _list(
        _item(),
        next:
            'home.php?mod=space&amp;do=favorite&amp;type=all&amp;page=${int.parse(url.queryParameters['page']!) + 1}',
      );
      await repo.sync();
      expect(transport.gets, hasLength(50));
      expect(index.items.single.targetId, 80);
    });
    test('补favid同步期间有其他写操作,取消失败而不误报成功', () async {
      index.put(_thread);
      index.merge([_entry(_forum, favid: '2002')]);
      final pending = Completer<String>();
      transport.get = (url) => url.queryParameters['do'] == 'favorite'
          ? pending.future
          : _form(deleting: true);
      transport.response = _message('删除成功');
      final removing = repo.remove(_thread);
      final expectation = expectLater(removing, throwsA(isA<StateError>()));
      await Future<void>.delayed(Duration.zero);
      await repo.remove(_forum);
      pending.complete(_list(''));
      await expectation;
      expect(index.contains(_thread), isTrue);
      expect(transport.posts, hasLength(1));
    });
    test('请求过程中换账号拒绝提交,不污染新账号', () async {
      transport.get = (_) {
        index.setUid(8);
        return _form();
      };
      await expectLater(repo.add(_thread), throwsA(isA<StateError>()));
      expect(transport.posts, isEmpty);
      expect(index.items, isEmpty);
    });
  });
}
