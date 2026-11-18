/// 更新服务地址与响应签名公钥
///
/// 正式通道优先使用服务器下发并验签通过的地址,再用构建注入地址;
/// 其他通道只用构建注入地址,避免测试安装被线上服务计入统计。
/// 服务器换 IP 或端口时,先在旧服务器的配置里下发新地址,已安装的客户端下次检查就会切换;
/// 新地址写进本地构建配置，公共源码不内置服务地址。
library;

/// 未注入地址时整个更新功能停用，持久化地址不能自行启用更新。
const String _definedEndpoints = String.fromEnvironment('CHH_UPDATE_ENDPOINTS');

List<String> get injectedUpdateEndpoints =>
    normalizeEndpoints(_definedEndpoints.split(','));

({bool isOfficial, List<String> endpoints}) resolveUpdateChannel({
  required String? packageName,
  required bool isRelease,
  required Iterable<String> injectedEndpoints,
  required Iterable<String> storedEndpoints,
}) {
  final isOfficial = packageName == 'com.chhreader.chh_app' && isRelease;
  final injected = normalizeEndpoints(injectedEndpoints);
  return (
    isOfficial: isOfficial,
    endpoints: normalizeEndpoints([
      if (injected.isNotEmpty && isOfficial) ...storedEndpoints,
      ...injected,
    ]),
  );
}

/// 服务器用私钥签名每个响应;客户端只认这里的公钥(ECDSA P-256 SubjectPublicKeyInfo)。
/// 换密钥时先在这里加新 kid 并发版,等旧版本基本升级完再让服务器改用新 kid。
const Map<String, String> updatePublicKeys = {
  'k1':
      'MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE/78wN59oC99b/ClQxqXJQKC/dq63Qc8AGNJMTwd0huQPjuxjhkZkqBfWq2Jt/4fedMhTfxd89+V8lQD7iUFUTg==',
};

/// 只接受 http(s)://host[:port] 形式,去掉末尾斜杠与重复项,保持原有顺序
List<String> normalizeEndpoints(Iterable<String> raw) {
  final out = <String>[];
  for (final value in raw) {
    final trimmed = value.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment) {
      continue;
    }
    final base = uri.origin;
    if (!out.contains(base)) out.add(base);
  }
  return out;
}
