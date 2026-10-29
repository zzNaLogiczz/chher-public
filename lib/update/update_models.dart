/// 更新协议的数据模型,与 server/update 的签名响应一一对应
///
/// 解析只发生在签名验证通过之后;字段缺失或类型不对一律当作无效响应,
/// 不猜默认值。
library;

import 'update_endpoints.dart';

class UpdateFormatException implements Exception {
  final String field;
  const UpdateFormatException(this.field);
  @override
  String toString() => 'UpdateFormatException($field)';
}

T _field<T>(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is T) return value;
  throw UpdateFormatException(key);
}

int _positive(Map<String, dynamic> json, String key) {
  final value = _field<int>(json, key);
  if (value <= 0) throw UpdateFormatException(key);
  return value;
}

/// 服务器下发的客户端配置:地址列表可以随时更换,无需发版
class UpdateServerConfig {
  final List<String> endpoints;
  final int checkIntervalHours;
  const UpdateServerConfig({
    required this.endpoints,
    required this.checkIntervalHours,
  });

  factory UpdateServerConfig.fromJson(Map<String, dynamic> json) {
    final raw = json['endpoints'];
    final hours = json['checkIntervalHours'];
    return UpdateServerConfig(
      endpoints: raw is List
          ? normalizeEndpoints(raw.whereType<String>())
          : const [],
      checkIntervalHours: hours is int && hours > 0 && hours <= 24 * 30
          ? hours
          : 24,
    );
  }
}

/// 检查版本接口的结果
class UpdateCheck {
  final int issuedAt;
  final int versionCode;
  final bool update;
  final bool force;
  final int? latestVersionCode;
  final String? latestVersionName;
  final UpdateServerConfig config;

  const UpdateCheck({
    required this.issuedAt,
    required this.versionCode,
    required this.update,
    required this.force,
    this.latestVersionCode,
    this.latestVersionName,
    required this.config,
  });

  factory UpdateCheck.fromJson(Map<String, dynamic> json) {
    if (json['type'] != 'check') throw const UpdateFormatException('type');
    final latest = json['latest'];
    final update = _field<bool>(json, 'update');
    if (update && latest is! Map<String, dynamic>) {
      throw const UpdateFormatException('latest');
    }
    final config = json['config'];
    return UpdateCheck(
      issuedAt: _positive(json, 'issuedAt'),
      versionCode: _positive(json, 'versionCode'),
      update: update,
      force: _field<bool>(json, 'force'),
      latestVersionCode: update ? _positive(latest!, 'versionCode') : null,
      latestVersionName: update ? _field<String>(latest!, 'versionName') : null,
      config: UpdateServerConfig.fromJson(
        config is Map<String, dynamic> ? config : const {},
      ),
    );
  }
}

/// 更新信息接口的结果:更新内容 + 限时下载链接
class UpdateRelease {
  final int versionCode;
  final String versionName;
  final String notes;
  final String publishedAt;
  final int minSupported;
  final String abi;
  final int size;
  final String sha256;

  /// 服务器签发的下载路径(带过期时间和签名),拼在 [endpoint] 后使用
  final String path;
  final int expiresAt;

  /// 这条信息来自哪个服务地址;下载走同一个地址
  final String endpoint;

  const UpdateRelease({
    required this.versionCode,
    required this.versionName,
    required this.notes,
    required this.publishedAt,
    required this.minSupported,
    required this.abi,
    required this.size,
    required this.sha256,
    required this.path,
    required this.expiresAt,
    required this.endpoint,
  });

  Uri get downloadUri => Uri.parse('$endpoint$path');

  factory UpdateRelease.fromJson(
    Map<String, dynamic> json, {
    required String endpoint,
  }) {
    if (json['type'] != 'release') throw const UpdateFormatException('type');
    final file = json['file'];
    if (file is! Map<String, dynamic>) {
      throw const UpdateFormatException('file');
    }
    final sha = _field<String>(file, 'sha256').toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha)) {
      throw const UpdateFormatException('sha256');
    }
    final path = _field<String>(file, 'path');
    if (!path.startsWith('/v1/download/')) {
      throw const UpdateFormatException('path');
    }
    final minSupported = json['minSupported'];
    return UpdateRelease(
      versionCode: _positive(json, 'versionCode'),
      versionName: _field<String>(json, 'versionName'),
      notes: (json['notes'] as String?)?.trim() ?? '',
      publishedAt: (json['publishedAt'] as String?) ?? '',
      minSupported: minSupported is int ? minSupported : 0,
      abi: _field<String>(file, 'abi'),
      size: _positive(file, 'size'),
      sha256: sha,
      path: path,
      expiresAt: _positive(file, 'expiresAt'),
      endpoint: endpoint,
    );
  }
}
