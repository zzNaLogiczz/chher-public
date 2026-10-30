/// 用户组门槛是全站资料,退出账号后继续复用。
library;

import 'dart:convert';
import 'dart:io';

import '../core/chh_urls.dart';
import '../network/chh_client.dart';
import '../parser/space_parser.dart';

class _Level {
  final String name;
  final int lowerCredits;
  final DateTime fetchedAt;
  const _Level(this.name, this.lowerCredits, this.fetchedAt);
}

class UserGroupLevels {
  final ChhClient client;
  final DateTime Function() _now;
  File? _file;
  final _levels = <int, _Level>{};
  final _pending = <int, Future<int?>>{};
  Future<void>? _loading;
  Future<void> _writes = Future<void>.value();
  static const _ttl = Duration(days: 7);

  /// 注入目录和时钟即可离线验证,不经过平台通道。
  UserGroupLevels(this.client, {Directory? directory, DateTime Function()? now})
    : _file = directory == null
          ? null
          : File('${directory.path}/levels-v1.json'),
      _now = now ?? DateTime.now;

  Future<void> attach(Directory? directory) async {
    // 先合并前一次读取,避免它晚到后漏写到新目录。
    await _loading;
    _file = directory == null ? null : File('${directory.path}/levels-v1.json');
    _loading = null;
    await _load();
    if (_levels.isNotEmpty) await _persist();
  }

  /// 同组请求合并;存储与网络失败都退回旧值,不阻塞资料展示。
  Future<int?> lowerCredits(int gid) {
    if (gid <= 0) return Future<int?>.value(null);
    return _pending.putIfAbsent(
      gid,
      () => _lookup(gid).whenComplete(() {
        _pending.remove(gid);
      }),
    );
  }

  Future<int?> _lookup(int gid) async {
    await _load();
    final old = _levels[gid];
    if (old != null && _now().difference(old.fetchedAt) < _ttl) {
      return old.lowerCredits;
    }
    try {
      final html = await client.getHtml(
        Uri.parse('${ChhUrls.base}/home.php?mod=spacecp&ac=usergroup&gid=$gid'),
        refresh: true,
      );
      final level = parseUserGroupLevel(html);
      if (level != null) {
        _levels[gid] = _Level(level.name, level.lowerCredits, _now());
        await _persist();
        return level.lowerCredits;
      }
    } catch (_) {
      // 没有权限、离线和损坏页面均可留到下次访问再试。
    }
    return _levels[gid]?.lowerCredits ?? old?.lowerCredits;
  }

  Future<void> _load() => _loading ??= _read();

  Future<void> _read() async {
    final file = _file;
    if (file == null) return;
    try {
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map || decoded['version'] != 1) return;
      final groups = decoded['groups'];
      if (groups is! Map) return;
      for (final entry in groups.entries) {
        final gid = int.tryParse(entry.key.toString());
        final value = entry.value;
        if (gid == null || gid <= 0 || value is! Map) continue;
        final name = value['name'];
        final lower = value['lowerCredits'];
        final at = value['fetchedAt'];
        if (name is! String || name.isEmpty || lower is! int || at is! int) {
          continue;
        }
        final fetchedAt = DateTime.fromMillisecondsSinceEpoch(at);
        final existing = _levels[gid];
        // 接线前已请求成功的资料优先于盘上旧值。
        if (existing == null || fetchedAt.isAfter(existing.fetchedAt)) {
          _levels[gid] = _Level(name, lower, fetchedAt);
        }
      }
    } catch (_) {
      // 损坏文件按空字典处理,首个成功请求会原子替换它。
    }
  }

  Future<void> _persist() => _writes = _writes.then((_) async {
    // 接线读盘期间的请求可以先完成,落盘须等旧字典合并后再快照。
    await _load();
    final file = _file;
    if (file == null) return;
    try {
      final payload = jsonEncode({
        'version': 1,
        'groups': _levels.map(
          (gid, level) => MapEntry('$gid', {
            'name': level.name,
            'lowerCredits': level.lowerCredits,
            'fetchedAt': level.fetchedAt.millisecondsSinceEpoch,
          }),
        ),
      });
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(payload, flush: true);
      await temporary.rename(file.path);
    } catch (_) {
      // 目录不可写时内存字典仍可使用。
    }
  });
}

/// 差额反推上限;缺少有效区间时保留未知状态。
double? userGroupProgress({
  required int lowerCredits,
  required int credits,
  required int remainingCredits,
}) {
  final upper = credits + remainingCredits;
  if (upper <= lowerCredits || credits < lowerCredits) return null;
  return ((credits - lowerCredits) / (upper - lowerCredits)).clamp(0.0, 1.0);
}
