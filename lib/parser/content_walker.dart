/// 正文 DOM → ContentBlock 列表
///
/// Discuz 正文(td#postmessage_XXX)的关键形态:
/// - 图片:<img zoomfile="..." file="..." src="占位图"> —— 真实地址优先取 zoomfile/file
/// - 引用:<div class="quote"><blockquote>...</blockquote></div>,首部有 <blockquote>xxx 发表于 ...
/// - 段落边界:p / br / div / li / tr;表情与站点图标(static/image/smiley|common)丢弃
/// - 链接:帖子、文章、B 站视频变成段落后的卡片,其余留在句子里可点(规则见 link_target.dart)
library;

import 'package:html/dom.dart' as dom;

import '../core/chh_urls.dart';
import '../core/link_target.dart';
import '../models/models.dart';
import 'dom_utils.dart';

const _skipTags = {'script', 'style', 'svg', 'button'};
const _skipClasses = {
  'fico-image', 'fico-thread', 'showcontent', 'tdpre', 'jammer',
  // 附件说明挂在图片的悬浮提示里(文件名、大小、下载次数、上传时间),
  // 页面上本来就是 display:none,不该出现在正文
  'aimg_tip', 'tip_horn', 'attach_nopermission', 'attach_tips',
  // 编辑说明与补充内容单独解析展示,不混在正文里
  'pstatus',
};
const _paragraphTags = {
  'p',
  'br',
  'div',
  'li',
  'tr',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'table',
};

/// [threadId] 限定论坛正文解析上下文，不用于补造引文缺失的目标 TID。
/// 显式跨帖引用仍保留原目标，聚合层需另行校验是否属于当前主题。
List<ContentBlock> parseContentBlocks(dom.Element root, {int? threadId}) =>
    _parseContentBlocks(root, threadId: threadId, insideQuote: false);

List<ContentBlock> _parseContentBlocks(
  dom.Element root, {
  int? threadId,
  required bool insideQuote,
}) => _BlockWalker(threadId: threadId, insideQuote: insideQuote).run(root);

/// 裸网址只取 RFC 3986 允许的 ASCII 字符,紧跟的中文不会被吞进去
final _bareUrl = RegExp(r"https?://[A-Za-z0-9\-._~:/?#\[\]@!$&'()*+,;=%]+");

/// 句末标点和不成对的右括号属于句子,不属于网址
String _trimUrl(String url) {
  var out = url;
  while (out.isNotEmpty) {
    final last = out[out.length - 1];
    final unpaired =
        last == ')' && '('.allMatches(out).length < ')'.allMatches(out).length;
    if (!'.,;:!?\''.contains(last) && !unpaired) break;
    out = out.substring(0, out.length - 1);
  }
  return out;
}

final _urlText = RegExp(r'^https?://\S+$');

class _BlockWalker {
  final int? threadId;

  /// 引用是摘录:里面的链接只留文字,不出卡片也不可点
  final bool insideQuote;

  _BlockWalker({required this.threadId, required this.insideQuote});

  final out = <ContentBlock>[];
  final _buf = StringBuffer();
  // 表情、链接与文字是穿插的,所以按内联片段收集,不能像图片那样单独成块
  final _inline = <InlineNode>[];
  var _hasInline = false;

  /// 本段有没有卡片之外的内容;只有卡片链接的段落整段由卡片替代
  var _hasOther = false;

  /// 本段结束时追加在段落后面的卡片
  final _cards = <ContentBlock>[];

  /// 同一楼层同一目标只出一张卡片
  final _seen = <String>{};

  List<ContentBlock> run(dom.Element root) {
    for (final child in root.nodes) {
      _walk(child);
    }
    _flush();
    return out;
  }

  void _pushText() {
    final t = _buf.toString();
    if (t.isNotEmpty) _inline.add(InlineText(t));
    _buf.clear();
  }

  void _write(String text, {bool other = true}) {
    _buf.write(text);
    if (other && text.trim().isNotEmpty) _hasOther = true;
  }

  void _flush() {
    _pushText();
    final text = _normalize(
      _inline
          .map(
            (e) => switch (e) {
              InlineText(:final text) => text,
              InlineLink(:final text) => text,
              InlineSmiley() => '',
            },
          )
          .join(),
    );
    if (_hasOther && (text.isNotEmpty || _hasInline)) {
      out.add(
        TextBlock(text, nodes: _hasInline ? _trimInline(_inline) : const []),
      );
    }
    out.addAll(_cards);
    _cards.clear();
    _inline.clear();
    _hasInline = false;
    _hasOther = false;
  }

  /// 帖子、文章、视频变成段落后的卡片;重复目标只保留第一张
  void _addCard(LinkTarget target, String label) {
    if (!_seen.add(target.key)) return;
    _cards.add(switch (target) {
      BilibiliVideo() => BilibiliBlock(target),
      _ => SiteLinkBlock(target, label: label),
    });
  }

  void _addInlineLink(String text, LinkTarget target) {
    _pushText();
    _inline.add(InlineLink(text, target));
    _hasInline = true;
    _hasOther = true;
  }

  void _walk(dom.Node node) {
    if (node is dom.Text) {
      insideQuote ? _write(node.text) : _walkText(node.text);
      return;
    }
    if (node is! dom.Element) return;
    final tag = node.localName?.toLowerCase() ?? '';
    // 站点把 B 站视频渲染成一段写入播放器 iframe 的脚本,其余脚本照旧丢弃
    if ((tag == 'script' || tag == 'iframe') && !insideQuote) {
      final video = bilibiliFromEmbed(
        tag == 'script' ? node.text : node.attributes['src'] ?? '',
      );
      if (video != null) _addCard(video, '');
      return;
    }
    if (_skipTags.contains(tag)) return;
    final cls = node.className;
    if (cls.split(' ').any(_skipClasses.contains)) return;
    // 页面上隐藏的内容一律不进正文
    if (_isHidden(node)) return;

    if (tag == 'div' && node.classes.contains('locked')) {
      _flush();
      final text = cleanLockedText(node);
      if (text.isNotEmpty) {
        out.add(QuoteBlock([TextBlock(text)], isNotice: true));
      }
      return;
    }
    if (tag == 'img') return _walkImage(node);
    if (_isQuote(node)) return _walkQuote(node, tag);
    if (tag == 'a' && !insideQuote && _walkAnchor(node)) return;
    if (_paragraphTags.contains(tag)) _flush();
    for (final child in node.nodes) {
      _walk(child);
    }
    if (_paragraphTags.contains(tag)) _flush();
  }

  void _walkImage(dom.Element node) {
    // 表情留在行内,不能当成独立图片块,否则一句话会被表情切碎
    final smiley = _smileyUrl(node);
    if (smiley != null) {
      _pushText();
      _inline.add(InlineSmiley(smiley));
      _hasInline = true;
      _hasOther = true;
      return;
    }
    _flush();
    final url = _imageUrl(node);
    if (url != null) out.add(ImageBlock(url));
  }

  /// 引用块:整块转 QuoteBlock,内部递归解析
  void _walkQuote(dom.Element node, String tag) {
    _flush();
    final inner = tag == 'blockquote'
        ? node
        : (node.children
                  .where((child) => child.localName == 'blockquote')
                  .firstOrNull ??
              node);
    out.add(
      QuoteBlock(
        _parseContentBlocks(inner, threadId: threadId, insideQuote: true),
        source: _quoteSource(node),
        reference: insideQuote || threadId == null
            ? null
            : _quoteReference(inner),
      ),
    );
  }

  /// 处理了返回 true;包着图片或不是可打开的链接时返回 false,按普通元素继续走
  bool _walkAnchor(dom.Element node) {
    if (node.querySelector('img') != null) return false;
    final target = classifyLink(node.attributes['href'] ?? '');
    if (target == null) return false;
    final text = _normalize(node.text);
    final isUrlText = _urlText.hasMatch(text);
    switch (target) {
      case ThreadLink() || ArticleLink() || BilibiliVideo():
        // 网址文字由卡片代替;标题文字留在句子里,单独成段时整段由卡片替代
        if (!isUrlText) _write(text, other: false);
        _addCard(target, isUrlText ? '' : text);
      case OtherSiteLink() || ExternalLink():
        if (text.isEmpty) return false;
        _addInlineLink(text, target);
    }
    return true;
  }

  /// 文字里没被 <a> 包住的网址同样识别
  void _walkText(String text) {
    var last = 0;
    for (final m in _bareUrl.allMatches(text)) {
      _write(text.substring(last, m.start));
      final url = _trimUrl(m.group(0)!);
      last = m.start + url.length;
      final target = classifyLink(url);
      if (target == null) {
        _write(url);
        continue;
      }
      switch (target) {
        case ThreadLink() || ArticleLink() || BilibiliVideo():
          _addCard(target, '');
        case OtherSiteLink() || ExternalLink():
          _addInlineLink(url, target);
      }
    }
    _write(text.substring(last));
  }
}

bool _isQuote(dom.Element element) =>
    element.localName == 'blockquote' ||
    (element.localName == 'div' &&
        element.className.split(RegExp(r'\s+')).contains('quote'));

/// 只检查引用第一行署名；不扫描摘录正文或嵌套旧引文中的地址。
/// 引用可被手工编辑，因此即便成功也仅是 claimed reference。
PostReference? _quoteReference(dom.Element quote) {
  final signature = StringBuffer();
  final links = <dom.Element>[];
  var stopped = false;

  void readHeader(dom.Node node) {
    if (stopped) return;
    if (node is dom.Text) {
      signature.write(node.text);
      return;
    }
    if (node is! dom.Element) return;
    final tag = node.localName ?? '';
    if (_isQuote(node) || tag == 'br') {
      stopped = true;
      return;
    }
    if (_skipTags.contains(tag) || _isHidden(node)) return;
    final block = _paragraphTags.contains(tag);
    if (block && signature.toString().trim().isNotEmpty) {
      stopped = true;
      return;
    }
    if (tag == 'a' && node.attributes.containsKey('href')) links.add(node);
    for (final child in node.nodes) {
      readHeader(child);
    }
    if (block) stopped = true;
  }

  for (final child in quote.nodes) {
    readHeader(child);
  }
  // 仅接受上游引用表单的作者 + 发表时间形态。普通文章引文降级为原文。
  final signaturePattern = RegExp(r'^.{1,60}?发表于\s*\d{4}-\d{1,2}-\d{1,2}');
  if (!signaturePattern.hasMatch(_normalize(signature.toString()))) {
    return null;
  }

  final base = Uri.parse(ChhUrls.base);
  final candidates = <Uri>[];
  final candidateLabels = <String>[];
  for (final link in links) {
    final raw = link.attributes['href'] ?? '';
    final parsed = Uri.tryParse(raw);
    if (parsed == null) continue;
    final url = base.resolveUri(parsed);
    // 统计所有声明 findpost 的链接，包括外域/冲突参数；混合目标不能选一条猜。
    if (url.queryParametersAll['goto']?.contains('findpost') ?? false) {
      candidates.add(url);
      candidateLabels.add(_normalize(link.text));
    }
  }
  if (candidates.length != 1 ||
      !signaturePattern.hasMatch(candidateLabels.single)) {
    return null;
  }
  final url = candidates.single;
  if (url.scheme != 'https' ||
      url.host != base.host ||
      url.port != base.port ||
      url.userInfo.isNotEmpty ||
      url.path != '/forum.php') {
    return null;
  }
  final query = url.queryParametersAll;
  // 重复参数即使值相同也不取；tid 与 ptid 并存同样保守降级。
  if (query.values.any((values) => values.length != 1) ||
      query['mod']?.single != 'redirect' ||
      query['goto']?.single != 'findpost' ||
      (query.containsKey('tid') && query.containsKey('ptid'))) {
    return null;
  }
  int? positiveId(String? raw) {
    if (raw == null || !RegExp(r'^[1-9]\d*$').hasMatch(raw)) return null;
    return int.tryParse(raw);
  }

  final pid = positiveId(query['pid']?.single);
  final tid = positiveId(query['ptid']?.single ?? query['tid']?.single);
  if (pid == null || tid == null) return null;
  return PostReference(tid: tid, pid: pid, url: url.toString());
}

/// 引用块的署名行("xxx 发表于 ..." / "引用:xxx")
String? _quoteSource(dom.Element quoteDiv) {
  final bq = quoteDiv.localName == 'blockquote'
      ? quoteDiv
      : quoteDiv.children
            .where((child) => child.localName == 'blockquote')
            .firstOrNull;
  if (bq == null) return null;
  final first = bq.nodes
      .whereType<dom.Element>()
      .where((e) => e.localName != 'div' || !e.className.contains('quote'))
      .firstOrNull;
  // Discuz 惯例:署名在 blockquote 首行 <div><blockquote>xxx 发表于 ... </blockquote></div> 或纯文本
  final text = _normalize(bq.text);
  final m = RegExp(r'^(.{1,30}?发表于.{0,20})').firstMatch(text);
  return m?.group(1) ?? first?.text.trim();
}

/// 论坛表情
///
/// 站点形态:<img src="static/image/smiley/diy/fd.gif" smilieid="390">
/// 以 smilieid 为准,路径作兜底 —— 属性比路径稳。
String? _smileyUrl(dom.Element img) {
  final src = img.attributes['src']?.trim() ?? '';
  if (src.isEmpty) return null;
  final isSmiley =
      img.attributes.containsKey('smilieid') ||
      src.contains('static/image/smiley');
  return isSmiley ? ChhUrls.absolutize(src) : null;
}

/// 去掉内联序列首尾的空白片段,中间的空格要留着
List<InlineNode> _trimInline(List<InlineNode> nodes) {
  final out = <InlineNode>[];
  for (final n in nodes) {
    if (n is InlineText) {
      final t = n.text.replaceAll(RegExp(r'[\s\u00a0]+'), ' ');
      if (t.trim().isEmpty && (out.isEmpty || out.last is InlineText)) continue;
      out.add(InlineText(t));
    } else {
      out.add(n);
    }
  }
  while (out.isNotEmpty &&
      out.last is InlineText &&
      (out.last as InlineText).text.trim().isEmpty) {
    out.removeLast();
  }
  return out;
}

String? _imageUrl(dom.Element img) {
  final candidates = [
    img.attributes['zoomfile'],
    img.attributes['file'],
    img.attributes['data-src'],
    img.attributes['data-original'],
    img.attributes['src'],
  ];
  for (final raw in candidates) {
    final u = raw?.trim() ?? '';
    if (u.isEmpty) continue;
    if (u.contains('static/image/common')) continue; // 站点图标
    return ChhUrls.absolutize(u);
  }
  return null;
}

String _normalize(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

/// 行内样式标了 display:none 的节点,用户在网页上看不到,正文也不该有
bool _isHidden(dom.Element el) {
  final style = el.attributes['style'];
  if (style == null) return false;
  return style.replaceAll(' ', '').contains('display:none');
}
