/// 更新服务地址与响应签名公钥
///
/// 正式通道优先使用服务器下发并验签通过的地址,再用构建注入与内置地址;
/// 其他通道只用构建注入地址,避免测试安装被线上服务计入统计。
/// 服务器换 IP 或端口时,先在旧服务器的配置里下发新地址,已安装的客户端下次检查就会切换;
/// 新地址也写进这里,保证全新安装和旧地址全部失效时仍能找到服务。
library;

/// 构建时覆盖:--dart-define=CHH_UPDATE_ENDPOINTS=http://1.2.3.4:8080,http://5.6.7.8:8080
const String _definedEndpoints = String.fromEnvironment('CHH_UPDATE_ENDPOINTS');

/// 内置地址(IP:端口,按优先级排列)。
/// 端口避开 80(国内运营商对 80 端口明文 HTTP 有劫持与透明缓存)和常被占用、扫描的 8080/8888 等
const List<String> _builtInEndpoints = ['http://115.159.191.32:27080'];

List<String> get injectedUpdateEndpoints =>
    normalizeEndpoints(_definedEndpoints.split(','));

List<String> get builtInUpdateEndpoints =>
    normalizeEndpoints(_builtInEndpoints);

({bool isOfficial, List<String> endpoints}) resolveUpdateChannel({
  required String? packageName,
  required bool isRelease,
  required Iterable<String> injectedEndpoints,
  required Iterable<String> storedEndpoints,
  required Iterable<String> builtInEndpoints,
}) {
  final isOfficial = packageName == 'com.chhreader.chh_app' && isRelease;
  return (
    isOfficial: isOfficial,
    endpoints: normalizeEndpoints([
      if (isOfficial) ...storedEndpoints,
      ...injectedEndpoints,
      if (isOfficial) ...builtInEndpoints,
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
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment) {
      continue;
    }
    final base =
        '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
    if (!out.contains(base)) out.add(base);
  }
  return out;
}
