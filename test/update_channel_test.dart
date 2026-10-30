import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:chh_app/update/update_client.dart';
import 'package:chh_app/update/update_controller.dart';
import 'package:chh_app/update/update_endpoints.dart';
import 'package:chh_app/update/update_models.dart';
import 'package:chh_app/update/update_platform.dart';
import 'package:chh_app/update/update_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const _officialPackage = 'com.chhreader.chh_app';
const _injected = 'https://injected.invalid';
const _stored = 'https://stored.invalid';
const _builtIn = 'https://built-in.invalid';
const _pushed = 'https://pushed.invalid';

const _release = UpdateRelease(
  versionCode: 154,
  versionName: '0.15.4',
  notes: '',
  publishedAt: '',
  minSupported: 0,
  abi: 'arm64-v8a',
  size: 1,
  sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  path: '/v1/download/154/arm64-v8a',
  expiresAt: 2000,
  endpoint: _injected,
);

void main() {
  group('update channel selection', () {
    test('official releases retain stored, injected and built-in order', () {
      final channel = resolveUpdateChannel(
        packageName: _officialPackage,
        isRelease: true,
        injectedEndpoints: const [' $_injected/ ', _stored],
        storedEndpoints: const [_stored, _stored],
        builtInEndpoints: const [_builtIn, _injected],
      );
      expect(channel.isOfficial, isTrue);
      expect(channel.endpoints, [_stored, _injected, _builtIn]);
    });

    for (final (packageName, isRelease) in [
      (_officialPackage, false),
      ('com.chhreader.chh_app.preview', true),
      ('com.chhreader.chh_app.qa', true),
      ('', true),
      (null, true),
    ]) {
      test('$packageName release=$isRelease uses only injected addresses', () {
        final channel = resolveUpdateChannel(
          packageName: packageName,
          isRelease: isRelease,
          injectedEndpoints: const [' $_injected/ ', _injected],
          storedEndpoints: const [_stored],
          builtInEndpoints: const [_builtIn],
        );
        expect(channel.isOfficial, isFalse);
        expect(channel.endpoints, [_injected]);
      });

      test('$packageName release=$isRelease needs explicit addresses', () {
        final channel = resolveUpdateChannel(
          packageName: packageName,
          isRelease: isRelease,
          injectedEndpoints: const [],
          storedEndpoints: const [_stored],
          builtInEndpoints: const [_builtIn],
        );
        expect(channel.endpoints, isEmpty);
      });
    }

    test('invalid injected addresses do not enable a test channel', () {
      final channel = resolveUpdateChannel(
        packageName: _officialPackage,
        isRelease: false,
        injectedEndpoints: const ['', 'ftp://invalid', 'https://host/path'],
        storedEndpoints: const [_stored],
        builtInEndpoints: const [_builtIn],
      );
      expect(channel.endpoints, isEmpty);
    });
  });

  group('update controller channels', () {
    late _FakePlatform platform;
    late _FakeClient client;
    late _MemoryStore store;

    UpdateController controller({
      bool isRelease = true,
      List<String> injected = const [_injected],
    }) {
      final result = UpdateController(
        platform: platform,
        client: client,
        injectedEndpoints: injected,
        builtInEndpoints: const [_builtIn],
        isRelease: isRelease,
        storeFor: (_) => store,
      );
      addTearDown(result.dispose);
      return result;
    }

    setUp(() {
      platform = _FakePlatform();
      client = _FakeClient(platform);
      store = _MemoryStore();
    });

    for (final (packageName, isRelease) in [
      (_officialPackage, false),
      ('com.chhreader.chh_app.preview', true),
      ('com.chhreader.chh_app.qa', true),
      ('', true),
    ]) {
      test(
        '$packageName release=$isRelease without injection stays offline',
        () async {
          platform.packageName = packageName;
          store.state = store.state.copyWith(
            endpoints: const [_stored],
            knownLatestVersionCode: 154,
          );
          final c = controller(isRelease: isRelease, injected: const []);
          expect(await c.checkOnLaunch(), isFalse);
          expect(c.available, isFalse);
          expect(c.endpoints, isEmpty);
          expect(c.hasUpdate, isFalse);
          await c.checkManually();
          expect(c.phase, UpdatePhase.failed);
          expect(c.failure, UpdateFailure.notConfigured);

          // 即使已有版本信息,未配置的通道也不能进入下载。
          c.release = _release;
          await c.download();
          expect(client.checks, isEmpty);
          expect(client.releases, isEmpty);
          expect(client.downloads, 0);
        },
      );

      test(
        '$packageName release=$isRelease ignores pushed addresses',
        () async {
          platform.packageName = packageName;
          store.state = store.state.copyWith(
            endpoints: const [_stored],
            endpointsIssuedAt: 100,
          );
          client.reply = _check(endpoints: const [_pushed], update: true);
          final c = controller(isRelease: isRelease);
          await c.checkManually();
          expect(c.phase, UpdatePhase.available);
          expect(client.checks, [
            const [_injected],
          ]);
          expect(client.releases, [
            const [_injected],
          ]);
          expect(c.endpoints, [_injected]);
          expect(store.state.endpoints, [_stored]);
          expect(store.state.endpointsIssuedAt, 100);
          expect(
            store.savedStates.every((s) => !s.endpoints.contains(_pushed)),
            isTrue,
          );
        },
      );
    }

    test(
      'test channel does not persist newly pushed addresses in a fresh store',
      () async {
        platform.packageName = 'com.chhreader.chh_app.preview';
        client.reply = _check(endpoints: const [_pushed]);
        final c = controller();
        await c.checkManually();
        expect(store.state.endpoints, isEmpty);
        expect(store.state.endpointsIssuedAt, 0);
        expect(store.savedStates.every((s) => s.endpoints.isEmpty), isTrue);
      },
    );

    test(
      'official channel retains persistence, response priority and replay protection',
      () async {
        store.state = store.state.copyWith(endpoints: const [_stored]);
        client
          ..respondWith = _injected
          ..reply = _check(endpoints: const [_pushed], update: true);
        final c = controller();
        await c.checkManually();
        expect(client.checks.single, [_stored, _injected, _builtIn]);
        expect(client.releases.single, [_injected, _pushed, _builtIn]);
        expect(c.endpoints, [_injected, _pushed, _builtIn]);
        expect(store.state.endpoints, [_pushed]);
        expect(store.state.endpointsIssuedAt, 1000);
        expect(store.state.checkIntervalHours, 12);

        // 新进程从存储地址开始,旧响应不能覆盖已保存的新配置。
        client
          ..respondWith = null
          ..reply = _check(endpoints: const [_stored], issuedAt: 999);
        final next = controller();
        await next.checkManually();
        expect(client.checks.last, [_pushed, _injected, _builtIn]);
        expect(next.endpoints, [_pushed, _injected, _builtIn]);
        expect(store.state.endpoints, [_pushed]);
        expect(store.state.endpointsIssuedAt, 1000);
      },
    );

    test(
      'a pending package name cannot expose addresses or start a request',
      () async {
        final pendingIdentity = Completer<AppIdentity>();
        platform.pendingIdentity = pendingIdentity.future;
        final c = controller();
        var completed = false;
        final checking = c.checkManually().then((_) => completed = true);
        await Future<void>.delayed(Duration.zero);
        expect(completed, isFalse);
        expect(c.identity, isNull);
        expect(c.endpoints, isEmpty);
        expect(c.available, isFalse);
        expect(client.checks, isEmpty);

        pendingIdentity.complete(platform.id);
        await checking;
        expect(client.checks, [
          const [_injected, _builtIn],
        ]);
      },
    );

    test(
      'failed package lookup stays unavailable even with injected addresses',
      () async {
        platform.identityError = StateError('appInfo unavailable');
        final c = controller();
        expect(await c.checkOnLaunch(), isFalse);
        await c.checkManually();
        expect(c.endpoints, isEmpty);
        expect(c.available, isFalse);
        expect(c.failure, UpdateFailure.notConfigured);
        expect(client.checks, isEmpty);
        expect(client.releases, isEmpty);
        expect(client.downloads, 0);
      },
    );
  });
}

UpdateCheck _check({
  List<String> endpoints = const [],
  int issuedAt = 1000,
  bool update = false,
}) => UpdateCheck(
  issuedAt: issuedAt,
  versionCode: 153,
  update: update,
  force: false,
  latestVersionCode: update ? 154 : null,
  latestVersionName: update ? '0.15.4' : null,
  config: UpdateServerConfig(endpoints: endpoints, checkIntervalHours: 12),
);

class _MemoryStore extends UpdateStore {
  _MemoryStore() : super(File('/unused/update/state.json'));

  UpdateState state = const UpdateState(
    installId: '00000000000000000000000000000000',
    lastSeenVersionCode: 153,
  );
  final savedStates = <UpdateState>[];

  @override
  Future<UpdateState> load() async => state;

  @override
  Future<void> save(UpdateState value) async {
    state = value;
    savedStates.add(value);
  }
}

class _FakeClient extends UpdateClient {
  _FakeClient(UpdatePlatform platform) : super(platform: platform);

  UpdateCheck reply = _check();
  String? respondWith;
  final checks = <List<String>>[];
  final releases = <List<String>>[];
  int downloads = 0;

  @override
  Future<(String, UpdateCheck)> check(
    List<String> endpoints, {
    required int versionCode,
    required String abi,
    required String installId,
  }) async {
    checks.add(List.of(endpoints));
    return (respondWith ?? endpoints.first, reply);
  }

  @override
  Future<UpdateRelease> release(
    List<String> endpoints, {
    required int versionCode,
    required String abi,
  }) async {
    releases.add(List.of(endpoints));
    return _release;
  }

  @override
  Future<File> download(
    UpdateRelease release,
    Directory dir, {
    required DownloadProgress onProgress,
    required Future<UpdateRelease> Function() refreshLink,
    CancelToken? cancel,
  }) async {
    downloads++;
    throw const UpdateException(UpdateFailure.notConfigured);
  }
}

class _FakePlatform implements UpdatePlatform {
  String packageName = _officialPackage;
  Future<AppIdentity>? pendingIdentity;
  Object? identityError;

  AppIdentity get id => AppIdentity(
    packageName: packageName,
    versionCode: 153,
    versionName: '0.15.3',
    abi: 'arm64-v8a',
    filesDir: '/unused',
    cacheDir: '/unused',
  );

  @override
  Future<AppIdentity> identity() async {
    if (identityError case final error?) throw error;
    return pendingIdentity ?? Future.value(id);
  }

  @override
  Future<bool> verifySignature(Uint8List k, Uint8List p, Uint8List s) async =>
      true;

  @override
  Future<ApkInspection> inspectApk(String path) async => const ApkInspection();

  @override
  Future<bool> canInstall() async => false;

  @override
  Future<bool> openInstallPermission() async => false;

  @override
  Future<bool> install(String path) async => false;

  @override
  Stream<InstallStatus> get installStatus => const Stream.empty();
}
