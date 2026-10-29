/// 页面获取器抽象:直连 / 隐藏 WebView / 本地文件 三种实现统一接口
library;

class ChhResponse {
  final int status;
  final String body;

  /// 失败原因。拿不到响应时三种情况要分开,否则排查时只能看到一个笼统的空响应:
  /// 超时、引擎内异常(如跨域被拒)、站点拦截。
  final String? error;

  /// 响应里的 Set-Cookie 原文
  ///
  /// 直连登录成功后要把这些 Cookie 写回 WebView 共享仓,
  /// 否则登录态只存在于 dio 这一侧,其余页面仍是游客。
  final List<String> setCookies;

  const ChhResponse(
    this.status,
    this.body, {
    this.error,
    this.setCookies = const [],
  });

  /// 超时的统一形态
  static const ChhResponse timeout = ChhResponse(-1, '', error: '请求超时');

  /// 请求是否在进入站点业务逻辑**之前**就被拒
  ///
  /// 只有这类响应才允许换通道重发。判错代价是重复发帖,所以从严:
  /// **空响应体不算未处理**。POST 收到 3xx 空响应恰恰说明站点受理了并让你跳转,
  /// 之前把它当成「没发出去」而补发一次,结果撞上站点的发表间隔限制。
  bool get rejectedBeforeApp {
    // 传输层就失败了,请求没能送达
    if (status <= 0) return true;
    // WAF 自定义状态码
    if (status == 567) return true;
    // 拦截页 / 机器人挑战页 / Discuz 初始化阶段的拒绝页
    return body.contains('Invalid Request') ||
        body.contains('remote_addr') ||
        body.contains('.a1{margin:0') ||
        body.contains('含有非法字符') ||
        body.contains('EO_Bot_Ssid');
  }

  /// CHH WAF 拦截页特征:自定义 567 状态码,或拦截页里的 remote_addr / .a1{ 样式
  bool get isBlocked =>
      status == 567 ||
      status <= 0 ||
      body.isEmpty ||
      body.contains('remote_addr') ||
      body.contains('Invalid Request') ||
      body.contains('.a1{margin:0');
}

abstract class ChhFetcher {
  String get name;

  /// 返回 HTML;由调用方(ChhClient)检查 [ChhResponse.isBlocked] 决定是否降级。
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers});

  /// 表单 POST(登录等写操作);默认不支持,由需要的实现覆盖。
  /// 走 WebView 实现:Credentialed fetch,Cookie 自动落入共享 Cookie 仓。
  Future<ChhResponse> postForm(Uri url, Map<String, String> form) async {
    throw UnsupportedError('$name 不支持 POST');
  }

  /// 文件上传(multipart);默认不支持,只有能自带文件体的通道覆盖
  Future<ChhResponse> postMultipart(
    Uri url,
    Map<String, String> fields,
    UploadFile file,
  ) async {
    throw UnsupportedError('$name 不支持上传文件');
  }

  Future<void> dispose() async {}
}

/// multipart 里的一个文件项
class UploadFile {
  final String field;
  final String filename;
  final String contentType;
  final List<int> bytes;

  const UploadFile({
    required this.field,
    required this.filename,
    required this.contentType,
    required this.bytes,
  });
}

class ChhAllBlockedError implements Exception {
  final String url;
  ChhAllBlockedError(this.url);

  @override
  String toString() => '所有获取器均被拦/失败: $url';
}
