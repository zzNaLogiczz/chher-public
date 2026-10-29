/// 更新相关的本地状态:放在应用 files 目录,不随缓存清理丢失
///
/// 只有安装标识(随机数,用于灰度分组)、服务器下发的地址、检查时间与忽略的版本,
/// 不含任何账号信息。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

class UpdateState {
  /// 随机安装标识,只用于灰度分桶
  final String installId;
  final List<String> endpoints;

  /// 地址列表的签发时间;只接受更新的下发,防止旧响应被重放覆盖
  final int endpointsIssuedAt;
  final int checkIntervalHours;
  final int lastCheckAt;
  final int ignoredVersionCode;

  /// 上次启动时的版本号;变大说明刚完成更新
  final int lastSeenVersionCode;

  /// 最近一次检查得知的最新版本号;0 表示已是最新。
  /// 启动检查有间隔,记下来才能在两次检查之间继续提示有新版本
  final int knownLatestVersionCode;

  const UpdateState({
    required this.installId,
    this.endpoints = const [],
    this.endpointsIssuedAt = 0,
    this.checkIntervalHours = 24,
    this.lastCheckAt = 0,
    this.ignoredVersionCode = 0,
    this.lastSeenVersionCode = 0,
    this.knownLatestVersionCode = 0,
  });

  UpdateState copyWith({
    List<String>? endpoints,
    int? endpointsIssuedAt,
    int? checkIntervalHours,
    int? lastCheckAt,
    int? ignoredVersionCode,
    int? lastSeenVersionCode,
    int? knownLatestVersionCode,
  }) => UpdateState(
    installId: installId,
    endpoints: endpoints ?? this.endpoints,
    endpointsIssuedAt: endpointsIssuedAt ?? this.endpointsIssuedAt,
    checkIntervalHours: checkIntervalHours ?? this.checkIntervalHours,
    lastCheckAt: lastCheckAt ?? this.lastCheckAt,
    ignoredVersionCode: ignoredVersionCode ?? this.ignoredVersionCode,
    lastSeenVersionCode: lastSeenVersionCode ?? this.lastSeenVersionCode,
    knownLatestVersionCode:
        knownLatestVersionCode ?? this.knownLatestVersionCode,
  );

  Map<String, dynamic> toJson() => {
    'version': 1,
    'installId': installId,
    'endpoints': endpoints,
    'endpointsIssuedAt': endpointsIssuedAt,
    'checkIntervalHours': checkIntervalHours,
    'lastCheckAt': lastCheckAt,
    'ignoredVersionCode': ignoredVersionCode,
    'lastSeenVersionCode': lastSeenVersionCode,
    'knownLatestVersionCode': knownLatestVersionCode,
  };

  static String newInstallId([Random? random]) {
    final r = random ?? Random.secure();
    return List.generate(
      16,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  static UpdateState fromJson(Map<String, dynamic> json) {
    int read(String key) => json[key] is int ? json[key] as int : 0;
    final id = json['installId'];
    return UpdateState(
      installId: id is String && RegExp(r'^[0-9a-f]{32}$').hasMatch(id)
          ? id
          : newInstallId(),
      endpoints:
          (json['endpoints'] as List?)?.whereType<String>().toList() ??
          const [],
      endpointsIssuedAt: read('endpointsIssuedAt'),
      checkIntervalHours: read('checkIntervalHours') > 0
          ? read('checkIntervalHours')
          : 24,
      lastCheckAt: read('lastCheckAt'),
      ignoredVersionCode: read('ignoredVersionCode'),
      lastSeenVersionCode: read('lastSeenVersionCode'),
      knownLatestVersionCode: read('knownLatestVersionCode'),
    );
  }
}

class UpdateStore {
  final File file;
  UpdateStore(this.file);

  factory UpdateStore.inDirectory(String filesDir) =>
      UpdateStore(File('$filesDir/update/state.json'));

  Directory get downloadDir => Directory('${file.parent.path}/downloads');

  Future<UpdateState> load() async {
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic> && decoded['version'] == 1) {
        return UpdateState.fromJson(decoded);
      }
    } catch (_) {
      // 首次启动或文件损坏:重新开始,不影响使用
    }
    return UpdateState(installId: UpdateState.newInstallId());
  }

  /// 先写临时文件再改名,中途被杀不会留下半个 JSON
  Future<void> save(UpdateState state) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(state.toJson()), flush: true);
    await temporary.rename(file.path);
  }
}
