/// 直连通道的 Cookie 罐
///
/// 站点的写操作要求 formhash 与**同一会话的 Cookie** 配套:
/// 带 formhash 却不带 Cookie 会被判成 CSRF,回一张伪装成 Discuz 错误页的预制页
/// (503「含有非法字符」)。所以取页面时就要把 Set-Cookie 收下来,提交时原样带回。
library;

class CookieJar {
  final Map<String, String> _cookies = {};

  Map<String, String> get all => Map.unmodifiable(_cookies);

  bool get isEmpty => _cookies.isEmpty;

  /// 收下响应里的 Set-Cookie
  void absorb(Iterable<String> setCookieHeaders) {
    for (final raw in setCookieHeaders) {
      final c = parseSetCookie(raw);
      if (c == null) continue;
      // 站点用空值或 deleted 表示删除
      if (c.value.isEmpty || c.value == 'deleted') {
        _cookies.remove(c.name);
      } else {
        _cookies[c.name] = c.value;
      }
    }
  }

  void merge(Map<String, String> extra) {
    extra.forEach((k, v) {
      if (k.isNotEmpty && v.isNotEmpty) _cookies[k] = v;
    });
  }

  void clear() => _cookies.clear();

  /// 组装成请求头形态
  String? header() {
    if (_cookies.isEmpty) return null;
    return _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  /// 解析单条 Set-Cookie,只取名值对,属性一律忽略
  static ({String name, String value})? parseSetCookie(String raw) {
    final pair = raw.split(';').first.trim();
    final i = pair.indexOf('=');
    if (i <= 0) return null;
    final name = pair.substring(0, i).trim();
    if (name.isEmpty) return null;
    return (name: name, value: pair.substring(i + 1).trim());
  }
}
