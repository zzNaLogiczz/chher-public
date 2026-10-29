import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chh_app/design/theme.dart';
import 'package:chh_app/update/update_client.dart';
import 'package:chh_app/update/update_controller.dart';
import 'package:chh_app/update/update_endpoints.dart';
import 'package:chh_app/update/update_models.dart';
import 'package:chh_app/update/update_platform.dart';
import 'package:chh_app/update/update_store.dart';
import 'package:chh_app/widgets/update_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _sha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

/// 只认签名内容为 "good" 的响应;真实验签在原生层,另有 javac 交叉检查
class FakePlatform implements UpdatePlatform {
  AppIdentity id;
  bool installAllowed = true;
  ApkInspection? inspection;
  final installs = <String>[];
  var permissionOpened = 0;
  final status = StreamController<InstallStatus>.broadcast();

  FakePlatform(String filesDir, {int versionCode = 153})
    : id = AppIdentity(
        packageName: 'com.chhreader.chh_app',
        versionCode: versionCode,
        versionName: '0.15.${versionCode - 150}',
        abi: 'arm64-v8a',
        filesDir: filesDir,
        cacheDir: filesDir,
      );

  @override
  Future<AppIdentity> identity() async => id;
  @override
  Future<bool> verifySignature(Uint8List k, Uint8List p, Uint8List s) async =>
      utf8.decode(s) == 'good';
  @override
  Future<ApkInspection> inspectApk(String path) async =>
      inspection ??
      const ApkInspection(
        sha256: _sha,
        packageName: 'com.chhreader.chh_app',
        versionCode: 154,
        sameSigner: true,
      );
  @override
  Future<bool> canInstall() async => installAllowed;
  @override
  Future<bool> openInstallPermission() async {
    permissionOpened++;
    return true;
  }

  @override
  Future<bool> install(String path) async {
    installs.add(path);
    return true;
  }

  @override
  Stream<InstallStatus> get installStatus => status.stream;
}

class FakeServer {
  late HttpServer _server;
  String get base => 'http://127.0.0.1:${_server.port}';

  Map<String, dynamic> checkPayload = {};
  Map<String, dynamic> releasePayload = {};
  Uint8List apk = Uint8List.fromList(List.generate(300000, (i) => i % 251));
  bool badSignature = false;
  int? downloadStatus;
  int expiredOnce = 0;
  final requests = <String>[];
  final ranges = <String?>[];

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> close() => _server.close(force: true);

  String _envelope(Map<String, dynamic> payload) => jsonEncode({
    'kid': 'k1',
    'payload': base64Encode(utf8.encode(jsonEncode(payload))),
    'sig': base64Encode(utf8.encode(badSignature ? 'bad' : 'good')),
  });

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    requests.add('${request.uri}');
    final res = request.response;
    if (path == '/v1/check') {
      res.write(_envelope(checkPayload));
    } else if (path.startsWith('/v1/releases/')) {
      res.write(_envelope(releasePayload));
    } else if (path.startsWith('/v1/download/')) {
      ranges.add(request.headers.value('range'));
      if (expiredOnce > 0 && request.uri.queryParameters['s'] == 'old') {
        expiredOnce--;
        res.statusCode = 403;
      } else if (downloadStatus != null) {
        res.statusCode = downloadStatus!;
      } else {
        final range = request.headers.value('range');
        final ifRange = request.headers.value('if-range');
        if (range != null && ifRange == '"$_sha"') {
          final start = int.parse(range.substring(6, range.length - 1));
          res.statusCode = 206;
          res.headers.set(
            'content-range',
            'bytes $start-${apk.length - 1}/${apk.length}',
          );
          res.add(apk.sublist(start));
        } else {
          res.add(apk);
        }
      }
    } else {
      res.statusCode = 404;
    }
    await res.close();
  }

  void offer({
    int vc = 154,
    bool force = false,
    List<String> endpoints = const [],
    int issuedAt = 1000,
    String sig = 'fresh',
  }) {
    checkPayload = {
      'type': 'check',
      'issuedAt': issuedAt,
      'versionCode': 153,
      'update': true,
      'force': force,
      'latest': {'versionCode': vc, 'versionName': '0.15.4'},
      'config': {'endpoints': endpoints, 'checkIntervalHours': 12},
    };
    releasePayload = {
      'type': 'release',
      'issuedAt': issuedAt,
      'versionCode': vc,
      'versionName': '0.15.4',
      'notes': '评论区支持三种查看方式',
      'minSupported': 0,
      'file': {
        'abi': 'arm64-v8a',
        'size': apk.length,
        'sha256': _sha,
        'path': '/v1/download/$vc/arm64-v8a?e=1&s=$sig',
        'expiresAt': 2000,
      },
    };
  }

  void upToDate() => checkPayload = {
    'type': 'check',
    'issuedAt': 1000,
    'versionCode': 153,
    'update': false,
    'force': false,
    'latest': null,
    'config': {'endpoints': <String>[], 'checkIntervalHours': 24},
  };
}

void main() {
  late Directory tmp;
  late FakeServer server;
  late FakePlatform platform;
  var clock = DateTime(2026, 10, 28, 12);

  UpdateController controller({List<String>? endpoints}) => UpdateController(
    platform: platform,
    client: UpdateClient(
      platform: platform,
      publicKeys: {
        'k1': base64Encode([1, 2, 3]),
      },
      retryDelay: Duration.zero,
    ),
    builtInEndpoints: endpoints ?? [server.base],
    now: () => clock,
  );

  setUp(() async {
    // flutter_test 默认把 HttpClient 换成一律报错的模拟实现;这里要连本地假服务器
    HttpOverrides.global = _RealHttp();
    tmp = await Directory.systemTemp.createTemp('chh-update-test');
    server = FakeServer();
    await server.start();
    platform = FakePlatform(tmp.path);
    clock = DateTime(2026, 10, 28, 12);
  });

  tearDown(() async {
    await server.close();
    await tmp.delete(recursive: true);
  });

  test('endpoints keep only http(s) host:port bases, in order', () {
    expect(
      normalizeEndpoints([
        ' http://1.2.3.4:8080/ ',
        'ftp://x',
        'http://1.2.3.4:8080',
        'https://u.example.com',
        'http://h:1/path',
        '',
      ]),
      ['http://1.2.3.4:8080', 'https://u.example.com'],
    );
  });

  test('a dead endpoint falls through to the next one', () async {
    server.offer();
    final c = controller(endpoints: ['http://127.0.0.1:1', server.base]);
    await c.checkManually();
    expect(c.phase, UpdatePhase.available);
    expect(c.release!.notes, '评论区支持三种查看方式');
    expect(c.endpoints.first, server.base);
  });

  test('responses that fail signature verification are rejected', () async {
    server
      ..offer()
      ..badSignature = true;
    final c = controller();
    await c.checkManually();
    expect(c.phase, UpdatePhase.failed);
    expect(c.failure, UpdateFailure.untrusted);
  });

  test(
    'server-pushed endpoints persist, and only newer pushes apply',
    () async {
      server.offer(endpoints: ['http://198.51.100.2:9000'], issuedAt: 1000);
      final c = controller();
      await c.checkManually();
      expect(c.endpoints, contains('http://198.51.100.2:9000'));

      // 新进程:读回保存的地址;更旧的下发(重放)不能覆盖
      server.offer(endpoints: ['http://203.0.113.9:1'], issuedAt: 999);
      final next = controller();
      await next.checkManually();
      expect(next.endpoints, contains('http://198.51.100.2:9000'));
      expect(next.endpoints, isNot(contains('http://203.0.113.9:1')));
      final saved = await UpdateStore.inDirectory(tmp.path).load();
      expect(saved.endpoints, ['http://198.51.100.2:9000']);
      expect(saved.checkIntervalHours, 12);
    },
  );

  test('launch checks honour the interval; manual checks do not', () async {
    server.upToDate();
    final c = controller();
    expect(await c.checkOnLaunch(), isFalse);
    final before = server.requests.length;
    clock = clock.add(const Duration(hours: 1));
    expect(await c.checkOnLaunch(), isFalse);
    expect(server.requests.length, before);
    await c.checkManually();
    expect(server.requests.length, before + 1);
    expect(c.phase, UpdatePhase.upToDate);
  });

  test('an ignored version is not prompted at launch, unless forced', () async {
    server.offer();
    final c = controller();
    expect(await c.checkOnLaunch(), isTrue);
    await c.ignoreCurrent();
    clock = clock.add(const Duration(days: 2));
    final next = controller();
    expect(await next.checkOnLaunch(), isFalse);

    server.offer(force: true);
    clock = clock.add(const Duration(days: 2));
    final forced = controller();
    expect(await forced.checkOnLaunch(), isTrue);
    expect(forced.force, isTrue);
  });

  test('a found update keeps its red dot across throttled launches', () async {
    server.offer();
    final c = controller();
    await c.checkOnLaunch();
    expect(c.hasUpdate, isTrue);

    // 间隔内再启动不会检查,但上次记下的新版本仍然提示
    clock = clock.add(const Duration(hours: 1));
    final before = server.requests.length;
    final next = controller();
    expect(await next.checkOnLaunch(), isFalse);
    expect(server.requests.length, before);
    expect(next.hasUpdate, isTrue);
    expect(next.newerVersionKnown, isTrue);
  });

  test(
    'ignoring the version hides the dot, the about page still knows',
    () async {
      server.offer();
      final c = controller();
      await c.checkOnLaunch();
      await c.ignoreCurrent();
      expect(c.hasUpdate, isFalse);
      expect(c.newerVersionKnown, isTrue);
    },
  );

  test('the dot goes away once the new version is installed', () async {
    server.offer();
    await controller().checkOnLaunch();
    platform = FakePlatform(tmp.path, versionCode: 154);
    final updated = controller();
    await updated.takeJustUpdated();
    expect(updated.hasUpdate, isFalse);
    expect(updated.newerVersionKnown, isFalse);
  });

  test('a later up-to-date answer clears the remembered version', () async {
    server.offer();
    final c = controller();
    await c.checkOnLaunch();
    server.upToDate();
    await c.checkManually();
    expect(c.hasUpdate, isFalse);
    clock = clock.add(const Duration(hours: 1));
    final next = controller();
    await next.takeJustUpdated();
    expect(next.hasUpdate, isFalse);
  });

  test('download resumes from a partial file and then installs', () async {
    server.offer();
    final c = controller();
    await c.checkManually();
    final dir = Directory('${tmp.path}/update/downloads')
      ..createSync(recursive: true);
    File(
      '${dir.path}/chher-154.apk.part',
    ).writeAsBytesSync(server.apk.sublist(0, 120000));
    File('${dir.path}/chher-154.apk.part.sha256').writeAsStringSync(_sha);

    await c.download();
    expect(server.ranges.single, 'bytes=120000-');
    final apk = File('${dir.path}/chher-154.apk');
    expect(apk.readAsBytesSync(), server.apk);
    expect(platform.installs, [apk.path]);
    expect(c.phase, UpdatePhase.installing);
  });

  test('a partial file from another build is discarded', () async {
    server.offer();
    final c = controller();
    await c.checkManually();
    final dir = Directory('${tmp.path}/update/downloads')
      ..createSync(recursive: true);
    File('${dir.path}/chher-154.apk.part').writeAsBytesSync([9, 9, 9]);
    File('${dir.path}/chher-154.apk.part.sha256').writeAsStringSync('b' * 64);
    await c.download();
    expect(server.ranges.single, isNull);
    expect(File('${dir.path}/chher-154.apk').readAsBytesSync(), server.apk);
  });

  test('an expired link is refreshed once without losing progress', () async {
    server
      ..offer(sig: 'old')
      ..expiredOnce = 1;
    final c = controller();
    await c.checkManually();
    server.offer(sig: 'new');
    await c.download();
    expect(server.requests.where((r) => r.contains('/v1/releases/')).length, 2);
    expect(c.release!.path, endsWith('s=new'));
    expect(platform.installs, hasLength(1));
  });

  test('a traffic-capped server reports busy and keeps the offer', () async {
    server
      ..offer()
      ..downloadStatus = 503;
    final c = controller();
    await c.checkManually();
    await c.download();
    expect(c.phase, UpdatePhase.failed);
    expect(c.failure, UpdateFailure.busy);
    expect(c.release, isNotNull);
  });

  test(
    'install waits for permission, then verifies before handing over',
    () async {
      server.offer();
      platform.installAllowed = false;
      final c = controller();
      await c.checkManually();
      await c.download();
      expect(c.phase, UpdatePhase.needsPermission);
      expect(platform.installs, isEmpty);

      platform.installAllowed = true;
      await c.resumeAfterPermission();
      expect(platform.installs, hasLength(1));
    },
  );

  test('a mismatched package is deleted instead of installed', () async {
    server.offer();
    platform.inspection = const ApkInspection(
      sha256: _sha,
      packageName: 'com.chhreader.chh_app',
      versionCode: 154,
      sameSigner: false,
    );
    final c = controller();
    await c.checkManually();
    await c.download();
    expect(c.failure, UpdateFailure.signer);
    expect(platform.installs, isEmpty);
    expect(Directory('${tmp.path}/update/downloads').existsSync(), isFalse);
  });

  test('a finished update is announced once on the next launch', () async {
    await UpdateStore.inDirectory(tmp.path).save(
      UpdateState(
        installId: UpdateState.newInstallId(),
        lastSeenVersionCode: 153,
      ),
    );
    platform = FakePlatform(tmp.path, versionCode: 154);
    final c = controller();
    expect(await c.takeJustUpdated(), '0.15.4');
    expect(await controller().takeJustUpdated(), isNull);
  });

  test('without native support the feature stays quiet', () async {
    final c = UpdateController(
      platform: _BrokenPlatform(),
      builtInEndpoints: [server.base],
    );
    expect(await c.checkOnLaunch(), isFalse);
    await c.checkManually();
    expect(c.failure, UpdateFailure.notConfigured);
    expect(server.requests, isEmpty);
  });

  group('sheet', () {
    UpdateController offered({bool force = false}) {
      final c = controller();
      c
        ..phase = UpdatePhase.available
        ..force = force
        ..release = UpdateRelease.fromJson(
          (server..offer()).releasePayload,
          endpoint: server.base,
        );
      return c;
    }

    Future<void> pumpSheet(WidgetTester tester, UpdateController c) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => UpdateSheet.show(context, c),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows notes, size and the three choices', (tester) async {
      await pumpSheet(tester, offered());
      expect(find.text('发现新版本'), findsOneWidget);
      expect(find.textContaining('0.15.4，0.3 MB'), findsOneWidget);
      expect(find.text('评论区支持三种查看方式'), findsOneWidget);
      expect(find.text('立即更新'), findsOneWidget);
      expect(find.text('以后再说'), findsOneWidget);
      expect(find.text('忽略此版本'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a forced update offers no way to skip it', (tester) async {
      await pumpSheet(tester, offered(force: true));
      expect(find.text('立即更新'), findsOneWidget);
      expect(find.text('以后再说'), findsNothing);
      expect(find.text('忽略此版本'), findsNothing);
    });

    testWidgets('download progress and permission states render', (
      tester,
    ) async {
      final c = offered()
        ..phase = UpdatePhase.downloading
        ..received = 209715
        ..total = 314572;
      await pumpSheet(tester, c);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('0.2 / 0.3 MB'), findsOneWidget);
      expect(find.text('取消下载'), findsOneWidget);

      c.phase = UpdatePhase.needsPermission;
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      c.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('需要允许 Chher 安装应用'), findsOneWidget);
      await tester.tap(find.text('去开启'));
      expect(platform.permissionOpened, 1);
    });
  });
}

class _BrokenPlatform extends FakePlatform {
  _BrokenPlatform() : super('/nonexistent');
  @override
  Future<AppIdentity> identity() async => throw UnimplementedError();
}

class _RealHttp extends HttpOverrides {}
