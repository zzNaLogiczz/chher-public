/// 应用内更新的状态机:检查 → 有新版本 → 下载 → 核对 → 交给系统安装
///
/// 全局一份,下载在弹层关闭后继续进行;设置页和更新弹层都只是它的视图。
library;

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/app_log.dart';
import 'update_client.dart';
import 'update_endpoints.dart';
import 'update_models.dart';
import 'update_platform.dart';
import 'update_store.dart';

enum UpdatePhase {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  verifying,
  needsPermission,
  installing,
  failed,
}

final UpdateController appUpdater = UpdateController();

class UpdateController extends ChangeNotifier {
  final UpdatePlatform _platform;
  final UpdateClient _client;
  final List<String> _injectedEndpoints;
  final List<String> _builtInEndpoints;
  final bool _isRelease;
  final DateTime Function() _now;
  final UpdateStore Function(AppIdentity identity) _storeFor;

  UpdateController({
    UpdatePlatform? platform,
    UpdateClient? client,
    List<String>? injectedEndpoints,
    List<String>? builtInEndpoints,
    bool isRelease = kReleaseMode,
    DateTime Function()? now,
    UpdateStore Function(AppIdentity identity)? storeFor,
  }) : this._(
         platform ?? ChannelUpdatePlatform(),
         client,
         injectedEndpoints,
         builtInEndpoints,
         isRelease,
         now,
         storeFor,
       );

  UpdateController._(
    UpdatePlatform platform,
    UpdateClient? client,
    List<String>? injectedEndpoints,
    List<String>? builtInEndpoints,
    bool isRelease,
    DateTime Function()? now,
    UpdateStore Function(AppIdentity identity)? storeFor,
  ) : _platform = platform,
      _client = client ?? UpdateClient(platform: platform),
      _injectedEndpoints = injectedEndpoints ?? injectedUpdateEndpoints,
      _builtInEndpoints = builtInEndpoints ?? builtInUpdateEndpoints,
      _isRelease = isRelease,
      _now = now ?? DateTime.now,
      _storeFor = storeFor ?? ((id) => UpdateStore.inDirectory(id.filesDir));

  UpdatePhase phase = UpdatePhase.idle;
  UpdateRelease? release;
  UpdateFailure? failure;
  bool force = false;
  int received = 0;
  int total = 0;
  AppIdentity? identity;

  late final Future<void> _ready = _init();
  late UpdateStore _store;
  late UpdateState _state;
  String? _respondingEndpoint;
  File? _apk;
  CancelToken? _cancel;
  StreamSubscription<InstallStatus>? _installSub;
  String? _justUpdatedFrom;

  /// 拿不到本机信息(非 Android、通道未注册)时整个功能静默停用
  bool get available => identity != null && _loaded && endpoints.isNotEmpty;
  bool _loaded = false;

  /// 已知有比当前更新的版本:本次检查拿到的,或上次检查记下、还没装上的
  bool get newerVersionKnown {
    if (!available) return false;
    final latest = release?.versionCode ?? _state.knownLatestVersionCode;
    return latest > identity!.versionCode;
  }

  /// 是否在入口上用红点提示:用户忽略过的版本不再提示,强制更新除外
  bool get hasUpdate {
    if (!newerVersionKnown) return false;
    final latest = release?.versionCode ?? _state.knownLatestVersionCode;
    return force || latest != _state.ignoredVersionCode;
  }

  Future<void> _init() async {
    try {
      identity = await _platform.identity();
    } catch (error) {
      AppLog.w('UPDATE', '更新不可用 ${error.runtimeType}');
      return;
    }
    _store = _storeFor(identity!);
    _state = await _store.load();
    final current = identity!.versionCode;
    if (_state.lastSeenVersionCode > 0 &&
        current > _state.lastSeenVersionCode) {
      _justUpdatedFrom = identity!.versionName;
      // 新版本已经装上,旧安装包没用了
      await _clearDownloads();
    }
    if (_state.lastSeenVersionCode != current) {
      _state = _state.copyWith(lastSeenVersionCode: current);
      await _save();
    }
    _loaded = true;
    // 读到上次记下的新版本号后,入口红点要立刻显示
    notifyListeners();
  }

  ({bool isOfficial, List<String> endpoints}) get _channel =>
      resolveUpdateChannel(
        packageName: identity?.packageName,
        isRelease: _isRelease,
        injectedEndpoints: _injectedEndpoints,
        storedEndpoints: _loaded ? _state.endpoints : const [],
        builtInEndpoints: _builtInEndpoints,
      );

  /// 包名与存储就绪后才开放地址;正式通道仍优先使用刚应答的地址
  List<String> get endpoints {
    if (!_loaded) return const [];
    final channel = _channel;
    return normalizeEndpoints([
      if (channel.isOfficial) ?_respondingEndpoint,
      ...channel.endpoints,
    ]);
  }

  bool get busy => const {
    UpdatePhase.checking,
    UpdatePhase.downloading,
    UpdatePhase.verifying,
    UpdatePhase.installing,
  }.contains(phase);

  /// 启动后调用一次:刚完成更新时返回新版本名,只返回一次
  Future<String?> takeJustUpdated() async {
    await _ready;
    if (!available) return null;
    final value = _justUpdatedFrom;
    _justUpdatedFrom = null;
    return value;
  }

  /// 冷启动检查:按服务器给的间隔节流,失败静默;返回是否应弹出更新提示
  Future<bool> checkOnLaunch() async {
    await _ready;
    if (!available || endpoints.isEmpty) return false;
    final elapsed = _now().millisecondsSinceEpoch - _state.lastCheckAt;
    if (elapsed >= 0 &&
        elapsed < Duration(hours: _state.checkIntervalHours).inMilliseconds) {
      return false;
    }
    await _check(manual: false);
    return phase == UpdatePhase.available &&
        (force || release!.versionCode != _state.ignoredVersionCode);
  }

  /// 设置页手动检查:不节流,结果都显示给用户
  Future<void> checkManually() async {
    await _ready;
    if (!available) {
      failure = UpdateFailure.notConfigured;
      _set(UpdatePhase.failed);
      return;
    }
    await _check(manual: true);
  }

  Future<void> _check({required bool manual}) async {
    if (busy) return;
    if (phase == UpdatePhase.available && !manual) return;
    _set(UpdatePhase.checking);
    try {
      final id = identity!;
      final (endpoint, check) = await _client.check(
        endpoints,
        versionCode: id.versionCode,
        abi: id.abi,
        installId: _state.installId,
      );
      _respondingEndpoint = endpoint;
      _applyServerConfig(check);
      _state = _state.copyWith(
        lastCheckAt: _now().millisecondsSinceEpoch,
        knownLatestVersionCode: check.update ? check.latestVersionCode : 0,
      );
      await _save();
      if (!check.update) {
        release = null;
        _set(UpdatePhase.upToDate);
        return;
      }
      release = await _client.release(
        endpoints,
        versionCode: check.latestVersionCode!,
        abi: id.abi,
      );
      force = check.force;
      _set(UpdatePhase.available);
    } on UpdateException catch (error) {
      AppLog.w('UPDATE', '检查失败 ${error.kind.name}');
      failure = error.kind;
      // 启动时的失败不打扰用户,下次启动再试
      _set(manual ? UpdatePhase.failed : UpdatePhase.idle);
    }
  }

  /// 只接受比已保存的更新的地址下发,旧响应被重放也不会把地址改回去
  void _applyServerConfig(UpdateCheck check) {
    if (!_channel.isOfficial) return;
    final config = check.config;
    if (config.endpoints.isEmpty ||
        check.issuedAt <= _state.endpointsIssuedAt) {
      return;
    }
    _state = _state.copyWith(
      endpoints: config.endpoints,
      endpointsIssuedAt: check.issuedAt,
      checkIntervalHours: config.checkIntervalHours,
    );
  }

  /// 下载并在完成后直接进入安装
  Future<void> download() async {
    await _ready;
    if (!available) {
      failure = UpdateFailure.notConfigured;
      _set(UpdatePhase.failed);
      return;
    }
    final target = release;
    if (target == null || busy) return;
    _cancel = CancelToken();
    received = 0;
    total = target.size;
    _set(UpdatePhase.downloading);
    try {
      _apk = await _client.download(
        target,
        _store.downloadDir,
        cancel: _cancel,
        onProgress: _progress,
        refreshLink: () async {
          // 下载链接过期:换一条新链接,已下载的部分不受影响
          final fresh = await _client.release(
            endpoints,
            versionCode: target.versionCode,
            abi: identity!.abi,
          );
          release = fresh;
          return fresh;
        },
      );
    } on UpdateException catch (error) {
      if (error.kind == UpdateFailure.cancelled) {
        _set(UpdatePhase.available);
      } else {
        failure = error.kind;
        _set(UpdatePhase.failed);
      }
      return;
    } finally {
      _cancel = null;
    }
    await install();
  }

  int _lastNotified = -1;
  void _progress(int value, int size) {
    received = value;
    total = size;
    // 千分位变化才刷新,避免每个网络包都重建界面
    final step = size == 0 ? 0 : value * 1000 ~/ size;
    if (step != _lastNotified) {
      _lastNotified = step;
      notifyListeners();
    }
  }

  void cancelDownload() => _cancel?.cancel();

  /// 核对安装包后交给系统安装器;没有安装权限时停下来等用户开启
  Future<void> install() async {
    final target = release;
    final apk = _apk;
    if (target == null || apk == null) return;
    if (!await _platform.canInstall()) {
      _set(UpdatePhase.needsPermission);
      return;
    }
    _set(UpdatePhase.verifying);
    final inspection = await _platform.inspectApk(apk.path);
    final id = identity!;
    final problem = inspection.sha256 != target.sha256
        ? UpdateFailure.integrity
        : inspection.packageName != id.packageName ||
              inspection.versionCode != target.versionCode ||
              target.versionCode <= id.versionCode
        ? UpdateFailure.integrity
        : !inspection.sameSigner
        ? UpdateFailure.signer
        : null;
    if (problem != null) {
      AppLog.w('UPDATE', '安装包核对未通过 ${problem.name}');
      await _clearDownloads();
      failure = problem;
      _set(UpdatePhase.failed);
      return;
    }
    _installSub ??= _platform.installStatus.listen(_onInstallStatus);
    _set(UpdatePhase.installing);
    if (!await _platform.install(apk.path)) {
      failure = UpdateFailure.install;
      _set(UpdatePhase.failed);
    }
  }

  void _onInstallStatus(InstallStatus status) {
    if (status == InstallStatus.failed && phase == UpdatePhase.installing) {
      failure = UpdateFailure.install;
      _set(UpdatePhase.failed);
    }
  }

  /// 用户从“允许安装未知应用”设置页返回后调用
  Future<void> resumeAfterPermission() async {
    if (phase != UpdatePhase.needsPermission) return;
    if (await _platform.canInstall()) await install();
  }

  Future<void> openInstallPermission() => _platform.openInstallPermission();

  /// 失败后重试:安装包已下好就直接安装,否则继续下载
  Future<void> retry() async {
    if (_apk != null && await _apk!.exists()) {
      await install();
    } else if (release != null) {
      await download();
    } else {
      await checkManually();
    }
  }

  Future<void> ignoreCurrent() async {
    final target = release;
    if (target == null || force) return;
    _state = _state.copyWith(ignoredVersionCode: target.versionCode);
    await _save();
    _set(UpdatePhase.idle);
  }

  /// 关闭提示:保留已获取的版本信息,设置页仍能继续
  void dismiss() {
    if (phase == UpdatePhase.upToDate || phase == UpdatePhase.failed) {
      _set(release == null ? UpdatePhase.idle : UpdatePhase.available);
    }
  }

  Future<void> _clearDownloads() async {
    try {
      final dir = _store.downloadDir;
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // 清理失败不影响使用,下次再清
    }
    _apk = null;
  }

  Future<void> _save() async {
    try {
      await _store.save(_state);
    } catch (error) {
      AppLog.w('UPDATE', '状态保存失败 ${error.runtimeType}');
    }
  }

  void _set(UpdatePhase next) {
    phase = next;
    if (next != UpdatePhase.failed) failure = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _installSub?.cancel();
    _cancel?.cancel();
    super.dispose();
  }
}
