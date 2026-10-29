/// Archiver 精简版帖子页 → 标题与发表时间
///
/// 正文卡片只要这两项。Archiver 页约 5KB,整页帖子约 60KB,所以卡片读它。
/// 形态:<div id="content"><p class="author"><strong>作者</strong> 发表于 2026-10-19 14:41</p><h3>标题</h3>
library;

import 'package:html/parser.dart' as html_parser;

import '../core/chh_urls.dart';

class ArchiverThreadMeta {
  final String title;
  final DateTime? time;
  const ArchiverThreadMeta({required this.title, this.time});
}

/// 无权限、已删除、登录墙等没有帖子内容的页面返回 null
ArchiverThreadMeta? parseArchiverThread(String html) {
  final doc = html_parser.parse(html);
  final content = doc.getElementById('content');
  final title = content?.querySelector('h3')?.text.trim() ?? '';
  if (title.isEmpty) return null;
  final author = content!.querySelector('p.author')?.text ?? '';
  return ArchiverThreadMeta(title: title, time: ChhUrls.parseTime(author));
}
