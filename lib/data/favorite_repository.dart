/// 收藏写操作只提交站点返回的表单,本地索引不额外探测阅读页。
library;

import 'dart:async';

import '../core/app_log.dart';
import '../core/chh_urls.dart';
import '../models/models.dart';
import '../network/chh_client.dart';
import '../parser/favorite_parser.dart';
import '../parser/space_parser.dart';
import 'favorite_index.dart';

export '../models/models.dart' show FavoriteItem, FavoriteType;
export 'favorite_index.dart';

class FavoriteRepository {
  final ChhClient client;
  final FavoriteIndex index;
  int _mutation = 0;

  FavoriteRepository(this.client, this.index);

  void _checkOwner(int epoch) {
    if (index.uid == null || index.epoch != epoch) {
      throw StateError('收藏账号已变化');
    }
  }

  Uri _operation(Map<String, String> fields) => ChhUrls.spacecp(
    ac: 'favorite',
  ).replace(queryParameters: {'mod': 'spacecp', 'ac': 'favorite', ...fields});

  Future<FavoriteToggle> add(FavoriteTarget target) async {
    await index.load();
    final epoch = index.epoch;
    _checkOwner(epoch);
    if (target.type == FavoriteType.all || target.targetId <= 0) {
      throw ArgumentError('收藏目标无效');
    }
    final url = _operation({
      'type': target.type.name,
      'id': '${target.targetId}',
    });
    final html = await client.getHtml(url, refresh: true);
    _checkOwner(epoch);
    if (isAlreadyFavorited(html)) {
      _mutation++;
      index.put(target);
      unawaited(sync());
      return const FavoriteToggle(true);
    }
    final form = parseFavoriteForm(html);
    if (form == null || !form.hidden.containsKey('favoritesubmit')) {
      throw parseFavoriteMessage(html) ?? StateError('没有收藏表单');
    }
    final response = await client.postForm(form.action, {
      ...form.hidden,
      'description': '',
      'favoritesubmit_btn': 'true',
    });
    _checkOwner(epoch);
    if (!isAlreadyFavorited(response.body) &&
        !_submissionSucceeded(response.body)) {
      // msgforward 可能直接跳回普通页面,只读复核,不重复提交。
      final verified = await client.getHtml(url, refresh: true);
      _checkOwner(epoch);
      if (!isAlreadyFavorited(verified)) {
        throw parseFavoriteMessage(verified) ?? StateError('收藏未完成');
      }
    }
    _mutation++;
    index.put(target);
    unawaited(sync(firstPageOnly: true));
    return const FavoriteToggle(true);
  }

  Future<FavoriteToggle> remove(FavoriteTarget target) async {
    await index.load();
    final epoch = index.epoch;
    _checkOwner(epoch);
    var favid = index.entryFor(target)?.favid;
    if (favid == null || favid.isEmpty) {
      // 不把同步失败当成「不存在」,否则界面会错误报告取消成功。
      await _synchronize(firstPageOnly: false);
      _checkOwner(epoch);
      favid = index.entryFor(target)?.favid;
    }
    if (favid != null && favid.isNotEmpty) {
      final url = _operation({'op': 'delete', 'favid': favid});
      final html = await client.getHtml(url, refresh: true);
      _checkOwner(epoch);
      final form = parseFavoriteForm(html);
      if (form == null) {
        if (!_absent(html)) {
          throw parseFavoriteMessage(html) ?? StateError('没有删除表单');
        }
      } else {
        if (!form.hidden.containsKey('deletesubmit')) {
          throw StateError('删除表单无效');
        }
        final response = await client.postForm(form.action, {
          ...form.hidden,
          'deletesubmitbtn': 'true',
        });
        _checkOwner(epoch);
        if (!_submissionSucceeded(response.body)) {
          final verified = await client.getHtml(url, refresh: true);
          _checkOwner(epoch);
          if (!_absent(verified)) {
            final message = parseFavoriteMessage(verified);
            if (message != null) throw message;
            final verificationForm = parseFavoriteForm(verified);
            if (verificationForm?.hidden.containsKey('deletesubmit') == true) {
              throw StateError('取消收藏未完成');
            }
          }
        }
      }
    }
    _checkOwner(epoch);
    _mutation++;
    index.remove(target);
    return const FavoriteToggle(false);
  }

  /// 明确消息直接采用;跳转后没有消息时由调用方复核状态。
  bool _submissionSucceeded(String html) {
    final message = parseFavoriteMessage(html);
    if (message == null) return false;
    if (message.text.contains('成功')) return true;
    throw message;
  }

  bool _absent(String html) {
    final message = parseFavoriteMessage(html);
    return message?.kind == PageMessageKind.message &&
        (message!.text.contains('不存在') ||
            message.text.contains('已删除') ||
            message.text.contains('未收藏') ||
            message.text.contains('已取消'));
  }

  /// 自动同步只记日志;未完成的分页不会覆盖已有索引。
  Future<void> sync({bool firstPageOnly = false}) async {
    try {
      await _synchronize(firstPageOnly: firstPageOnly);
    } catch (e) {
      AppLog.w('FAVORITE', '同步未完成 $e');
    }
  }

  Future<void> _synchronize({required bool firstPageOnly}) async {
    await index.load();
    if (index.uid == null) return;
    final epoch = index.epoch;
    final mutation = _mutation;
    final items = <FavoriteItem>[];
    var url = ChhUrls.favorite();
    final visited = <String>{};
    for (var page = 1; page <= 50; page++) {
      if (!visited.add(url.toString())) throw StateError('收藏分页重复');
      final result = parseFavorites(await client.getHtml(url, refresh: true));
      _checkOwner(epoch);
      items.addAll(result.items);
      if (firstPageOnly || !result.page.hasNext) {
        // 取列表期间若有写操作,留待下一次同步,不覆盖新状态。
        if (mutation != _mutation) throw StateError('同步期间收藏发生变化');
        if (firstPageOnly) {
          index.merge(items, prepend: true);
        } else {
          index.replace(items, syncedAt: DateTime.now());
        }
        return;
      }
      url = result.nextUrl != null
          ? Uri.parse(result.nextUrl!)
          : ChhUrls.favorite(page: page + 1);
    }
    throw StateError('收藏列表超过 50 页');
  }
}
