/// Archiver 精简版帖子页 → 标题、发表时间、作者与首段摘要。
/// 形态:<div id="content"><p class="author"><strong>作者</strong> 发表于 2026-10-19 14:41</p><h3>标题</h3>
library;

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../core/chh_urls.dart';
import 'post_note_parser.dart';

// Stop before Chinese prose/punctuation even when the URL has no surrounding
// spaces. Attachment URLs may be protocol-relative or Archiver-relative.
final _excerptUrls = RegExp(
  r'''(?:https?://|//|static\.chiphell\.com/|(?:/?(?:[\w.-]+/)*attachment\.php|forum\.php\?mod=attachment)(?=[?&#\s]|$))[^\s<>"'\u3000-\u303f\u3400-\u9fff\uff00-\uffef]*''',
  caseSensitive: false,
);
final _imagePath = RegExp(
  r'''^[/\w.%+-]+\.(?:jpe?g|png|gif|webp)(?:[?#][^\s]*)?$''',
  caseSensitive: false,
);
final _attachmentLabels = RegExp(
  r'(?:下载附件|保存到相册|上传)(?:\s*[（(][^()（）\n]*[)）])?',
);
final _uploadTime = RegExp(
  r'^\d{4}-\d{1,2}-\d{1,2}\s+\d{1,2}:\d{2}(?::\d{2})?\s+上传$',
);
final _excerptContent = RegExp(r'[\p{L}\p{N}\p{S}]', unicode: true);

class ArchiverThreadMeta {
  final String title;
  final DateTime? time;
  final String? author;
  final String? excerpt;
  const ArchiverThreadMeta({
    required this.title,
    this.time,
    this.author,
    this.excerpt,
  });
}

/// 无权限、已删除、登录墙等没有帖子内容的页面返回 null
ArchiverThreadMeta? parseArchiverThread(String html) {
  final doc = html_parser.parse(html);
  final content = doc.getElementById('content');
  final heading = content?.querySelector('h3');
  final title = heading?.text.trim() ?? '';
  if (title.isEmpty) return null;
  final authorRow = content!
      .querySelectorAll('p.author, h3')
      .takeWhile((node) => node != heading)
      .where((node) => node.classes.contains('author'))
      .firstOrNull;
  final author = authorRow?.querySelector('strong')?.text.trim();
  return ArchiverThreadMeta(
    title: title,
    time: ChhUrls.parseTime(authorRow?.text ?? ''),
    author: author == null || author.isEmpty ? null : author,
    excerpt: _firstParagraph(heading!),
  );
}

// Stop at the next author: a reply must never become the first post's excerpt.
String? _firstParagraph(dom.Element heading) {
  final siblings = heading.parentNode?.nodes ?? <dom.Node>[];
  return _readParagraph(siblings.skip(siblings.indexOf(heading) + 1));
}

String? _readParagraph(Iterable<dom.Node> nodes) {
  final text = StringBuffer();
  bool hasBody() {
    if (_cleanExcerpt(text.toString()).isEmpty) text.clear();
    return text.isNotEmpty;
  }

  for (final node in nodes) {
    if (node is dom.Element) {
      if (node.classes.contains('author') || node.localName == 'h3') break;
      if (_skipExcerptElement(node)) continue;
      if (node.localName == 'br') {
        if (hasBody()) break;
        continue;
      }
      if (['p', 'div'].contains(node.localName)) {
        if (hasBody()) break;
        final paragraph = node.querySelector('p, div') == null
            ? _cleanExcerpt(_plainText(node))
            : _readParagraph(node.nodes) ?? '';
        if (paragraph.isEmpty) continue;
        text.write(paragraph);
        break;
      }
    }
    text.write(_plainText(node));
  }
  if (!hasBody()) return null;
  final normalized = _cleanExcerpt(text.toString());
  return normalized.isEmpty
      ? null
      : String.fromCharCodes(normalized.runes.take(80));
}

String _cleanExcerpt(String raw) {
  final lines = <String>[];
  for (final line in raw.split(RegExp(r'[\r\n]+'))) {
    final text = line.trim();
    if (postEditedTime(text) != null || _uploadTime.hasMatch(text)) continue;
    final cleaned = text.replaceAll(_excerptUrls, '').trim();
    if (_imagePath.hasMatch(cleaned) ||
        !_excerptContent.hasMatch(cleaned) ||
        !_excerptContent.hasMatch(cleaned.replaceAll(_attachmentLabels, ''))) {
      continue;
    }
    lines.add(cleaned);
  }
  return lines.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _plainText(dom.Node node) {
  if (node is dom.Text) return node.data;
  if (node is! dom.Element || _skipExcerptElement(node)) return '';
  if (node.localName == 'br') return '\n';
  final text = node.nodes.map(_plainText).join();
  if (!['p', 'div'].contains(node.localName)) return text;
  if (postEditedTime(text.trim()) != null) return '';
  return text
      .split('\n')
      .where((line) => postEditedTime(line.trim()) == null)
      .join('\n');
}

bool _skipExcerptElement(dom.Element node) =>
    ['script', 'style', 'noscript', 'img'].contains(node.localName) ||
    node.classes.any(
      {'aimg_tip', 'tip_horn', 'attach_nopermission', 'attach_tips'}.contains,
    ) ||
    node.localName == 'i' && node.classes.contains('pstatus');
