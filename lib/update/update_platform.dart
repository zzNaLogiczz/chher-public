/// 应用内更新的系统能力:本机版本、签名验证、安装包核对、系统安装器
///
/// 生产实现走 Android 的 chh/update 通道;测试注入假实现,不触碰系统。
library;

import 'dart:async';

import 'package:flutter/services.dart';

class AppIdentity {
  final String packageName;
  final int versionCode;
  final String versionName;
  final String abi;
  final String filesDir;
  final String cacheDir;
  const AppIdentity({
    required this.packageName,
    required this.versionCode,
    required this.versionName,
    required this.abi,
    required this.filesDir,
    required this.cacheDir,
  });
}

/// 安装包核对结果;任何一项不符都不交给系统安装器
class ApkInspection {
  final String? sha256;
  final String? packageName;
  final int? versionCode;
  final bool sameSigner;
  const ApkInspection({
    this.sha256,
    this.packageName,
    this.versionCode,
    this.sameSigner = false,
  });
}

enum InstallStatus { pendingUserAction, success, failed }

abstract class UpdatePlatform {
  Future<AppIdentity> identity();
  Future<bool> verifySignature(
    Uint8List publicKey,
    Uint8List payload,
    Uint8List signature,
  );
  Future<ApkInspection> inspectApk(String path);
  Future<bool> canInstall();
  Future<bool> openInstallPermission();

  /// 提交给系统安装器;返回 false 表示没能提交
  Future<bool> install(String path);

  /// 系统安装器回报的状态;成功时进程通常会被系统直接结束
  Stream<InstallStatus> get installStatus;
}

class ChannelUpdatePlatform implements UpdatePlatform {
  static const _channel = MethodChannel('chh/update');
  final _status = StreamController<InstallStatus>.broadcast();

  ChannelUpdatePlatform() {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'installStatus') return;
      final args = Map<String, dynamic>.from(call.arguments as Map);
      _status.add(switch (args['status']) {
        'pending_user_action' => InstallStatus.pendingUserAction,
        'success' => InstallStatus.success,
        _ => InstallStatus.failed,
      });
    });
  }

  @override
  Future<AppIdentity> identity() async {
    final raw = Map<String, dynamic>.from(
      await _channel.invokeMethod<Map>('appInfo') ?? const {},
    );
    final abis = (raw['abis'] as List?)?.whereType<String>().toList() ?? [];
    return AppIdentity(
      packageName: raw['packageName'] as String,
      versionCode: (raw['versionCode'] as num).toInt(),
      versionName: (raw['versionName'] as String?) ?? '',
      abi: abis.isEmpty ? 'universal' : abis.first,
      filesDir: raw['filesDir'] as String,
      cacheDir: raw['cacheDir'] as String,
    );
  }

  @override
  Future<bool> verifySignature(
    Uint8List publicKey,
    Uint8List payload,
    Uint8List signature,
  ) async =>
      await _channel.invokeMethod<bool>('verifySignature', {
        'publicKey': publicKey,
        'payload': payload,
        'signature': signature,
      }) ??
      false;

  @override
  Future<ApkInspection> inspectApk(String path) async {
    final raw = Map<String, dynamic>.from(
      await _channel.invokeMethod<Map>('inspectApk', {'path': path}) ??
          const {},
    );
    return ApkInspection(
      sha256: raw['sha256'] as String?,
      packageName: raw['packageName'] as String?,
      versionCode: (raw['versionCode'] as num?)?.toInt(),
      sameSigner: raw['sameSigner'] == true,
    );
  }

  @override
  Future<bool> canInstall() async =>
      await _channel.invokeMethod<bool>('canInstall') ?? false;

  @override
  Future<bool> openInstallPermission() async =>
      await _channel.invokeMethod<bool>('openInstallPermission') ?? false;

  @override
  Future<bool> install(String path) async =>
      await _channel.invokeMethod<String>('install', {'path': path}) ==
      'started';

  @override
  Stream<InstallStatus> get installStatus => _status.stream;
}
