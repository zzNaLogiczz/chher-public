import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chh_app/data/user_group_levels.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:flutter_test/flutter_test.dart';

String _groupHtml(int lower) =>
    '''
<ul id="tba"><li id="c2">晋级用户组 - 能天使</li></ul>
<div class="tscr"><span class="notice">积分下限 $lower</span></div>
''';

class _Client extends ChhClient {
  int requests = 0;
  final urls = <Uri>[];
  String html = _groupHtml(2500);
  bool fail = false;
  Completer<void>? gate;

  _Client() : super(fetchers: []);

  @override
  Future<String> getHtml(
    Uri url, {
    bool refresh = false,
    bool fallback = true,
  }) async {
    requests++;
    urls.add(url);
    await gate?.future;
    if (fail) throw StateError('离线');
    return html;
  }
}

void main() {
  late Directory directory;
  late _Client client;
  late DateTime now;

  UserGroupLevels make({Directory? storage}) =>
      UserGroupLevels(client, directory: storage ?? directory, now: () => now);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('chh-group-levels-');
    client = _Client();
    now = DateTime.utc(2026, 10, 30);
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('首次请求按 gid 取页面并持久化字典', () async {
    expect(await make().lowerCredits(41), 2500);
    expect(client.requests, 1);
    expect(client.urls.single.queryParameters, {
      'mod': 'spacecp',
      'ac': 'usergroup',
      'gid': '41',
    });
    final stored = jsonDecode(
      await File('${directory.path}/levels-v1.json').readAsString(),
    );
    expect(stored['version'], 1);
    expect(stored['groups']['41'], {
      'name': '能天使',
      'lowerCredits': 2500,
      'fetchedAt': now.millisecondsSinceEpoch,
    });
    expect(File('${directory.path}/levels-v1.json.tmp').existsSync(), isFalse);
  });

  test('重启后七天内命中磁盘缓存而不请求', () async {
    expect(await make().lowerCredits(41), 2500);
    now = now.add(const Duration(days: 6, hours: 23));
    client.fail = true;
    expect(await make().lowerCredits(41), 2500);
    expect(client.requests, 1);
  });

  test('恰好七天过期重新请求并更新磁盘', () async {
    final levels = make();
    await levels.lowerCredits(41);
    now = now.add(const Duration(days: 7));
    client.html = _groupHtml(2600);
    expect(await levels.lowerCredits(41), 2600);
    expect(client.requests, 2);
    client.fail = true;
    expect(await make().lowerCredits(41), 2600);
    expect(client.requests, 2);
  });

  test('过期请求失败返回旧值', () async {
    final levels = make();
    await levels.lowerCredits(41);
    now = now.add(const Duration(days: 8));
    client.fail = true;
    expect(await levels.lowerCredits(41), 2500);
    expect(client.requests, 2);
  });

  test('无旧值请求失败返回 null', () async {
    client.fail = true;
    expect(await make().lowerCredits(41), isNull);
    expect(client.requests, 1);
  });

  test('同 gid 并发只请求一次', () async {
    final levels = make();
    client.gate = Completer<void>();
    final pending = List.generate(5, (_) => levels.lowerCredits(41));
    await Future<void>.delayed(Duration.zero);
    client.gate!.complete();
    expect(await Future.wait(pending), List.filled(5, 2500));
    expect(client.requests, 1);
  });

  test('不同 gid 并发的写盘不丢失其它组', () async {
    final levels = make();
    expect(
      await Future.wait([levels.lowerCredits(41), levels.lowerCredits(42)]),
      [2500, 2500],
    );
    final stored = jsonDecode(
      await File('${directory.path}/levels-v1.json').readAsString(),
    );
    expect((stored['groups'] as Map).keys.toSet(), {'41', '42'});
    expect(client.requests, 2);
  });

  test('损坏文件当空字典，成功后修复', () async {
    await File('${directory.path}/levels-v1.json').writeAsString('{oops');
    expect(await make().lowerCredits(41), 2500);
    expect(client.requests, 1);
    expect(await make().lowerCredits(41), 2500);
    expect(client.requests, 1);
  });

  test('消息页或空页不覆盖旧值', () async {
    final levels = make();
    await levels.lowerCredits(41);
    now = now.add(const Duration(days: 8));
    client.html = '<div id="messagetext"><p>请先登录</p></div>';
    expect(await levels.lowerCredits(41), 2500);
    client.html = '';
    expect(await levels.lowerCredits(42), isNull);
  });

  test('接线保留内存中的请求结果并写入新目录', () async {
    final levels = UserGroupLevels(client, now: () => now);
    expect(await levels.lowerCredits(41), 2500);
    await levels.attach(directory);
    expect(await make().lowerCredits(41), 2500);
    expect(client.requests, 1);
  });

  test('请求尚未完成时接线合并盘上其它组', () async {
    final disk = make();
    await disk.lowerCredits(42);
    final levels = UserGroupLevels(client, now: () => now);
    client.gate = Completer<void>();
    final request = levels.lowerCredits(41);
    await Future<void>.delayed(Duration.zero);
    await levels.attach(directory);
    client.gate!.complete();
    expect(await request, 2500);
    final stored = jsonDecode(
      await File('${directory.path}/levels-v1.json').readAsString(),
    );
    expect((stored['groups'] as Map).keys.toSet(), {'41', '42'});
  });

  test('请求失败时仍能使用请求期间接线读到的旧值', () async {
    await make().lowerCredits(41);
    now = now.add(const Duration(days: 8));
    final levels = UserGroupLevels(client, now: () => now);
    client.gate = Completer<void>();
    final request = levels.lowerCredits(41);
    await Future<void>.delayed(Duration.zero);
    await levels.attach(directory);
    client.fail = true;
    client.gate!.complete();
    expect(await request, 2500);
  });

  test('目录不可写时保留内存结果', () async {
    final blocked = File('${directory.path}/blocked');
    await blocked.writeAsString('x');
    final levels = make(storage: Directory('${blocked.path}/groups'));
    expect(await levels.lowerCredits(41), 2500);
    expect(await levels.lowerCredits(41), 2500);
    expect(client.requests, 1);
  });

  test('无效 gid 不请求', () async {
    final levels = make();
    expect(await levels.lowerCredits(0), isNull);
    expect(await levels.lowerCredits(-1), isNull);
    expect(client.requests, 0);
  });

  group('升级进度', () {
    test('以当前组下限和剩余积分计算', () {
      expect(
        userGroupProgress(
          lowerCredits: 2500,
          credits: 2880,
          remainingCredits: 1120,
        ),
        closeTo(0.253333, 0.000001),
      );
    });
    test('差额为零时到达 1', () {
      expect(
        userGroupProgress(
          lowerCredits: 2500,
          credits: 2880,
          remainingCredits: 0,
        ),
        1,
      );
    });
    test('无有效区间不计算', () {
      expect(
        userGroupProgress(
          lowerCredits: 2500,
          credits: 2499,
          remainingCredits: 1120,
        ),
        isNull,
      );
      expect(
        userGroupProgress(
          lowerCredits: 2500,
          credits: 2500,
          remainingCredits: 0,
        ),
        isNull,
      );
      expect(
        userGroupProgress(
          lowerCredits: 2500,
          credits: 2880,
          remainingCredits: -400,
        ),
        isNull,
      );
    });
    test('超过上限时夹到 1', () {
      expect(
        userGroupProgress(
          lowerCredits: 2500,
          credits: 2880,
          remainingCredits: -100,
        ),
        1,
      );
    });
  });
}
