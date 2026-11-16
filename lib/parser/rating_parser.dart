import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../core/chh_urls.dart';
import '../models/models.dart';
import 'dom_utils.dart';

/// Standard X3 rate_view table; the current site's template needs device QA.
List<RatingEntry> parseRatingDetails(String html) {
  final doc = html_parser.parse(html);
  if (detectPageMessage(doc) != null) return const [];
  final entries = <RatingEntry>[];
  for (final table in doc.querySelectorAll('table.list')) {
    for (final row in table.querySelectorAll('tr')) {
      final cells = row.children.where((c) => c.localName == 'td').toList();
      if (cells.length != 4) continue;
      final userIndex = cells.indexWhere((c) => findUserLink(c) != null);
      if (userIndex != 0 && userIndex != 1) continue;
      final user = findUserLink(cells[userIndex])!;
      final name = cleanText(user.el.text);
      final scoreText = cleanText(cells[1 - userIndex].text);
      final scores = RegExp(
        r'(?<![\d.])[+\-−]?\s*\d+(?![\d.])',
      ).allMatches(scoreText).toList();
      if (scores.length != 1) continue;
      final score = scores.single;
      final time = cleanText(cells[2].text);
      if (name.isEmpty || ChhUrls.parseTime(time) == null) {
        continue;
      }
      final credit = cleanText(
        scoreText.replaceRange(score.start, score.end, ''),
      );
      if (credit.isEmpty) continue;
      final reason = cells[3].clone(true);
      for (final br in reason.querySelectorAll('br')) {
        br.replaceWith(html_parser.parseFragment('\n'));
      }
      entries.add(
        RatingEntry(
          user: name,
          uid: user.uid,
          score: score.group(0)!.trim(),
          credit: credit,
          timeRaw: time,
          reason: reason.text.trim(),
        ),
      );
    }
  }
  return entries;
}

int? ratingScoreValue(String raw) =>
    int.tryParse(raw.replaceAll(RegExp(r'\s+'), '').replaceAll('−', '-'));

/// Content fallback for a full page, without assumptions about template names.
/// One parsed document serves all truncated entries from the requested floor.
class RatingContentPage {
  final int length;
  final dom.Document _doc;
  final _text = <dom.Element, String>{};
  final _secrets = <String>{};
  late final bool _messagePage;

  RatingContentPage(String html)
    : length = html.length,
      _doc = html_parser.parse(html) {
    _messagePage = detectPageMessage(_doc) != null;
    // Retain only visible structure. Attribute values are never logged, except
    // sanitized class/id identifiers; remember explicit secrets before removal.
    for (final element in _doc.querySelectorAll('*')) {
      for (final attr in element.attributes.entries) {
        if (_sensitive.hasMatch(attr.key.toString()) ||
            (attr.key == 'value' &&
                (element.attributes['type'] == 'hidden' ||
                    _sensitive.hasMatch(element.attributes['name'] ?? '') ||
                    _sensitive.hasMatch(element.id)))) {
          if (attr.value.isNotEmpty) _secrets.add(attr.value);
        }
        if (const {'href', 'src', 'action'}.contains(attr.key)) {
          final uri = Uri.tryParse(attr.value);
          for (final param
              in (uri?.queryParametersAll ?? <String, List<String>>{})
                  .entries) {
            if (_sensitive.hasMatch(param.key)) {
              _secrets.addAll(param.value.where((value) => value.isNotEmpty));
            }
          }
        }
      }
    }
    for (final element in _doc.querySelectorAll(
      'script, style, noscript, template, input, textarea, select, button, [hidden]',
    )) {
      element.remove();
    }
  }

  static final _dates = RegExp(
    r'\d{4}[-/.年]\d{1,2}[-/.月]\d{1,2}日?(?:[ T]+\d{1,2}:\d{2}(?::\d{2})?)?|\b\d{1,2}:\d{2}(?::\d{2})?\b',
  );
  static final _scores = RegExp(r'(?<![\d.+\-−])[+\-−]\s*\d+(?![\d.])');
  static final _sensitive = RegExp(
    r'cookie|token|formhash|password|passwd|authorization|session|ticket|secret',
    caseSensitive: false,
  );

  String _plain(dom.Element element) =>
      _text.putIfAbsent(element, () => cleanText(element.text));

  List<dom.Element> _names(RatingEntry target) {
    final name = cleanText(target.user);
    if (name.isEmpty) return [];
    return _doc.body?.querySelectorAll('*').where((element) {
          return _plain(element) == name &&
              !element.children.any((child) => _plain(child) == name);
        }).toList() ??
        [];
  }

  bool _hasScore(dom.Element element, RatingEntry target) {
    final value = ratingScoreValue(target.score);
    return value != null &&
        _scores
            .allMatches(_plain(element).replaceAll(_dates, ' '))
            .any((match) => ratingScoreValue(match[0]!) == value);
  }

  dom.Element? _row(dom.Element name, RatingEntry target) {
    for (dom.Element? node = name; node != null; node = node.parent) {
      final tag = node.localName;
      final row =
          const {'tr', 'li', 'dl', 'dd'}.contains(tag) ||
          (const {'div', 'p'}.contains(tag) && node.children.length > 1);
      if (row && _hasScore(node, target)) {
        // A header link must not turn the whole page/list into a rating row.
        if (node
            .querySelectorAll('tr, li, dl, dd, div, p')
            .any(
              (child) =>
                  !_contains(child, name) &&
                  _hasScore(child, target) &&
                  (const {'tr', 'li', 'dl'}.contains(child.localName) ||
                      child
                          .querySelectorAll('a')
                          .any((link) => cleanText(link.text).isNotEmpty) ||
                      _plain(child).contains(target.user)),
            )) {
          return null;
        }
        return node;
      }
      // Never borrow the score/reason from a neighbouring physical row.
      if (const {'tr', 'li', 'dd'}.contains(tag)) return null;
      if (tag == 'body') break;
    }
    return null;
  }

  bool hasAmbiguousMatch(RatingEntry target) {
    if (_messagePage) return false;
    final names = _names(target);
    final rows = names.map((name) => _row(name, target)).nonNulls.toSet();
    return rows.length > 1 ||
        (rows.length == 1 &&
            names.where((name) => _contains(rows.single, name)).length > 1);
  }

  String? reasonFor(RatingEntry target) {
    if (_messagePage || !isRatingReasonTruncated(target.reason)) return null;
    final names = _names(target);
    final rows = names.map((name) => _row(name, target)).nonNulls.toSet();
    if (rows.length != 1) return null;
    final row = rows.single;
    // A repeated identity inside one list container is ambiguous as well.
    if (names.where((name) => _contains(row, name)).length != 1) return null;

    // The observed four-column table is credit/score, user, time, reason
    // (some templates put the user first). Do not judge the reason's content.
    final cells = row.children.where((c) => c.localName == 'td').toList();
    if (row.localName == 'tr' && cells.length == 4) {
      return _readText(cells[3]).trim();
    }

    // Other templates place the reason after the identity/score/time fields.
    // Consume only that leading metadata, then retain the entire reason,
    // including nested spans, line breaks, dates, scores and trailing dots.
    final name = names.singleWhere((name) => _contains(row, name));
    var foundScore = false;
    var foundTime = false;
    var foundReason = false;
    String read(dom.Node node) {
      if (node == name) return '';
      if (node is dom.Element && _contains(node, name)) {
        return node.nodes.map(read).join();
      }
      if (foundReason) return _readText(node);
      if (!foundScore &&
          node is dom.Element &&
          node.children.any((child) => _hasScore(child, target))) {
        return node.nodes.map(read).join();
      }
      var text = _readText(node);
      if (!foundScore) {
        final dates = _dates.allMatches(text).toList();
        final score = _scores.allMatches(text).where((match) {
          return ratingScoreValue(match[0]!) ==
                  ratingScoreValue(target.score) &&
              !dates.any(
                (date) => match.start >= date.start && match.end <= date.end,
              );
        }).firstOrNull;
        if (score == null) return '';
        foundScore = true;
        text = text.substring(score.end).replaceFirst(RegExp(r'^\s*分'), '');
      }
      text = text.trimLeft();
      if (!foundTime && node is dom.Text) {
        // A mixed text node can contain both the timestamp and the reason.
        final date = _dates.matchAsPrefix(text);
        if (date != null) {
          foundTime = true;
          text = text.substring(date.end).trimLeft();
        }
      } else if (!foundTime &&
          _dates.firstMatch(text)?.group(0) == text.trimRight()) {
        foundTime = true;
        return '';
      }
      if (text.isEmpty) return '';
      foundReason = true;
      return text;
    }

    return row.nodes.map(read).join().trim();
  }

  static bool _contains(dom.Element parent, dom.Element child) {
    for (dom.Element? node = child; node != null; node = node.parent) {
      if (node == parent) return true;
    }
    return false;
  }

  static String _readText(dom.Node node) {
    if (node is dom.Text) return node.text;
    if (node is dom.Element && node.localName == 'br') return '\n';
    if (node is dom.Element &&
        node.localName == 'a' &&
        RegExp(
          r'^(?:查看全部|查看完整(?:理由|附言)?|展开|收起|更多)$',
        ).hasMatch(cleanText(node.text))) {
      return '';
    }
    return node.nodes.map(_readText).join();
  }

  /// Four bounded WARN messages; the repository handles session/TID deduping.
  List<String> diagnostics(RatingEntry target) {
    if (_messagePage) return const [];
    final names = _names(target);
    final name =
        names.where((name) => _row(name, target) != null).firstOrNull ??
        names.firstOrNull;
    final row = name == null ? null : _row(name, target);
    final block = row ?? name?.parent;
    final path = <String>[];
    for (dom.Element? node = name; node != null; node = node.parent) {
      path.add('${_label(node, id: true)}(${node.children.length})');
      if (node.localName == 'body') break;
    }
    final children =
        block?.children
            .take(12)
            .map((child) => '${_label(child)}:${_safe(_plain(child), 12)}')
            .join(' | ') ??
        'none';
    final parts = [
      (
        'meta',
        'len=$length title=${_safe(_doc.querySelector('title')?.text ?? '', 100)} '
            'user=${names.isNotEmpty} score=${_doc.body != null && _hasScore(_doc.body!, target)}',
        220,
      ),
      ('path', path.isEmpty ? 'none' : path.reversed.join(' > '), 580),
      (
        'row',
        '${block == null ? 'none' : _label(block, id: true)} $children',
        360,
      ),
      (
        'match',
        'names=${names.length} rows=${names.map((n) => _row(n, target)).nonNulls.toSet().length} '
            'messagePage=$_messagePage result=unresolved',
        120,
      ),
    ];
    return [
      for (var i = 0; i < parts.length; i++)
        '${i + 1}/4 ${parts[i].$1} ${_cut(parts[i].$2, parts[i].$3)}',
    ];
  }

  String _label(dom.Element element, {bool id = false}) {
    String identifier(String value) =>
        _sensitive.hasMatch(value) ? '[redacted]' : _safe(value, 24);
    return '${element.localName}'
        '${element.classes.take(2).map((c) => '.${identifier(c)}').join()}'
        '${id && element.id.isNotEmpty ? '#${identifier(element.id)}' : ''}';
  }

  String _safe(String text, int limit) {
    for (final secret in _secrets) {
      text = text.replaceAll(secret, '[redacted]');
    }
    // A text node may echo credentials or a link: redact before truncation.
    text = text.replaceAll(
      RegExp(
        r'''(?:https?://|(?:href|src)\s*=)[^\s<>"']+''',
        caseSensitive: false,
      ),
      '[url]',
    );
    text = text.replaceAll(
      RegExp(
        r'(?:cookie|token|formhash|password|passwd|authorization|session|ticket|secret)\b[^\r\n]*',
        caseSensitive: false,
      ),
      '[redacted]',
    );
    text = text.replaceAll(RegExp(r'[A-Za-z0-9_\-]{20,}'), '[redacted]');
    return _cut(cleanText(text), limit);
  }

  static String _cut(String text, int limit) => text.runes.length <= limit
      ? text
      : '${String.fromCharCodes(text.runes.take(limit - 1))}…';
}
