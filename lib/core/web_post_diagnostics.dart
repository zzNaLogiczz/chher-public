import 'app_log.dart';

/// WebView 回调只留下 URL 摘要及已知的表单状态。
class WebPostDiagnostics {
  static void opened(Uri page, Map<String, String> fields) =>
      AppLog.i('WEBPOST', '打开 ${AppLog.url(page)} ${AppLog.fields(fields)}');

  static void loaded(String page, String title) =>
      AppLog.i('WEBPOST', '加载 ${AppLog.url(page)} titleLength=${title.length}');

  static void filled(Map report) => AppLog.i(
    'WEBPOST',
    '已填表 action=${AppLog.url(report['action'])} '
        'seccode=${report['seccode'] is num ? report['seccode'] : '?'} '
        'verifyButton=${report['verifyButton'] == true} '
        'tcaptcha=${report['tcaptcha'] == 'function'}',
  );
  static void consoleError(String message) =>
      AppLog.w('WEBPOST', '页面报错 messageLength=${message.length}');

  static void loadError(Object? page, Object type) =>
      AppLog.w('WEBPOST', '加载失败 ${AppLog.url(page)} type=$type');
}
