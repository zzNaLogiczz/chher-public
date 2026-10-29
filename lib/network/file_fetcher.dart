/// 本地文件获取器:离线开发源
///
/// `flutter run --dart-define=chh_source=file` 启用:
/// 不访问线上、不被 WAF 影响、无网络也能开发调试 UI 与解析器。
/// URL → test_data/ 样本文件的映射见 [_fileFor]。
library;

import 'dart:io';

import 'chh_fetcher.dart';

class FileFetcher implements ChhFetcher {
  final String dir;
  FileFetcher({this.dir = 'test_data'});

  @override
  String get name => 'file';

  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) async {
    final f = _fileFor(url);
    if (f == null) return const ChhResponse(404, '');
    final file = File('$dir/$f');
    if (!await file.exists()) {
      return const ChhResponse(404, '');
    }
    return ChhResponse(200, await file.readAsString());
  }

  String? _fileFor(Uri url) {
    final u = url.toString();
    if (u.contains('search.php')) return 'search_synthetic.html';
    if (u.contains('mod=guide')) return 'guide_synthetic.html';
    if (u.contains('mod=logging')) return 'login_synthetic.html';
    if (u.contains('mod=forumdisplay')) {
      return (url.queryParameters['fid'] == '290' &&
              (url.queryParameters['page'] ?? '1') == '1')
          ? 'thread_list_synthetic.html'
          : null;
    }
    final m =
        RegExp(r'thread-(900001)-').firstMatch(u) ??
        RegExp(r'tid=(900001)').firstMatch(u);
    if (m != null) return 'thread_synthetic.html';
    if (u.contains('forum.php') && !url.queryParameters.containsKey('mod')) {
      return 'forum_index_synthetic.html';
    }
    return null;
  }

  @override
  Future<void> dispose() async {}

  @override
  Future<ChhResponse> postForm(Uri url, Map<String, String> form) async {
    return const ChhResponse(404, '');
  }

  @override
  Future<ChhResponse> postMultipart(
    Uri url,
    Map<String, String> fields,
    UploadFile file,
  ) async => const ChhResponse(404, '');
}
