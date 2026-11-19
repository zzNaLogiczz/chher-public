import 'package:html/dom.dart' as dom;

import '../core/display_time.dart';
import '../models/models.dart';

final _dateTime = RegExp(
  r'^(\d{4})-(\d{1,2})-(\d{1,2})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?$',
);
final _supplement = RegExp(r'^补充内容\s*[（(]([^）)]+)[）)]\s*[:：]\s*([\s\S]*)$');
final _edited = RegExp(
  r'^本帖最后由\s+.+?\s+于\s+(\d{4}-\d{1,2}-\d{1,2}\s+\d{1,2}:\d{2}(?::\d{2})?)\s+编辑$',
);

DateTime? _validTime(String raw) {
  final match = _dateTime.firstMatch(raw.trim());
  if (match == null) return null;
  final parts = [for (var i = 1; i <= 6; i++) int.parse(match[i] ?? '0')];
  final date = DateTime(
    parts[0],
    parts[1],
    parts[2],
    parts[3],
    parts[4],
    parts[5],
  );
  if (date.year != parts[0] ||
      date.month != parts[1] ||
      date.day != parts[2] ||
      date.hour != parts[3] ||
      date.minute != parts[4] ||
      date.second != parts[5]) {
    return null;
  }
  return date;
}

({String timeRaw, String text})? parseSupplement(String text) {
  final match = _supplement.firstMatch(text.trim());
  if (match == null || _validTime(match[1]!) == null) return null;
  final body = match[2]!
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(RegExp(r'\n[^\S\n]*\n(?:[^\S\n]*\n)*'), '\n\n')
      .trim();
  if (body.isEmpty) return null;
  return (timeRaw: match[1]!.trim(), text: body);
}

DateTime? postEditedTime(String text) {
  final raw = _edited.firstMatch(text.trim())?[1];
  return raw == null ? null : _validTime(raw);
}

bool showPostEdit(PostNote note, Post post) {
  if (note.kind != PostNoteKind.edited) return false;
  final edited = postEditedTime(note.text);
  final published = post.time ?? _validTime(post.timeRaw);
  return edited != null &&
      published != null &&
      edited.difference(published) >= const Duration(minutes: 10);
}

String? postEditedLabel(String text, {DateTime? now}) {
  final time = postEditedTime(text);
  return time == null ? null : '最后编辑于 ${formatDisplayTime(at: time, now: now)}';
}

/// Only site notices carry this meaning; quoted or ordinary author text does not.
bool isSuppressedPost(Post post) =>
    (post.lock != null && isSuppressedNoticeText(post.lock!.text)) ||
    post.content.whereType<QuoteBlock>().any(
      (block) =>
          block.isNotice &&
          isSuppressedNoticeText(
            block.children.whereType<TextBlock>().map((b) => b.text).join(' '),
          ),
    );

bool isSuppressedNoticeText(String text) =>
    RegExp(r'作者被(?:禁止|删除)').hasMatch(text) &&
    RegExp(r'内容.*(?:自动屏蔽|被屏蔽|已屏蔽)').hasMatch(text);

/// Unknown markup stays in the body instead of silently losing content.
PostNote? parsePostNoteElement(dom.Element element) {
  if (!element.classes.contains('pstatus') &&
      element.localName != 'p' &&
      element.localName != 'div') {
    return null;
  }
  if (element.querySelector('p, div') != null) return null;
  final text = _plainNoteText(element)?.trim();
  if (text == null || text.isEmpty) return null;
  if (parseSupplement(text) != null) {
    return PostNote(PostNoteKind.supplement, text);
  }
  if (element.classes.contains('pstatus') && postEditedTime(text) != null) {
    return PostNote(PostNoteKind.edited, text);
  }
  return null;
}

/// Discuz can put only the heading in pstatus and the body after a sibling br.
({PostNote note, int end})? parseSupplementSiblings(
  List<dom.Node> nodes,
  int start,
) {
  final first = nodes[start];
  if (first is dom.Element &&
      (first.querySelector('p, div') != null ||
          parsePostNoteElement(first) != null)) {
    return null;
  }
  final text = _plainNoteText(first)?.trim();
  final heading = text == null ? null : _supplement.firstMatch(text);
  if (heading == null || _validTime(heading[1]!) == null) return null;
  final out = StringBuffer(text!);
  var end = start;
  for (var i = start + 1; i < nodes.length; i++) {
    final next = _plainNoteText(nodes[i]);
    // Keep unsupported markup in the original body rather than losing context.
    if (next == null) return null;
    if (_supplement.hasMatch(next.trim()) ||
        nodes[i] is dom.Element &&
            parsePostNoteElement(nodes[i] as dom.Element) != null) {
      break;
    }
    if (nodes[i] is dom.Element &&
        {'p', 'div'}.contains((nodes[i] as dom.Element).localName)) {
      out.writeln();
    }
    out.write(next);
    end = i;
  }
  final result = out.toString().trim();
  return parseSupplement(result) == null
      ? null
      : (note: PostNote(PostNoteKind.supplement, result), end: end);
}

String? _plainNoteText(dom.Node element) {
  const inline = {'span', 'font', 'i', 'em', 'b', 'strong', 'u', 's', 'code'};
  final out = StringBuffer();
  var valid = true;
  void read(dom.Node node) {
    if (node is dom.Text) {
      out.write(node.text.replaceAll('\u00a0', ' '));
      return;
    }
    if (node is! dom.Element) return;
    final tag = node.localName;
    final style = (node.attributes['style'] ?? '')
        .replaceAll(RegExp(r'\s'), '')
        .toLowerCase();
    if (node.classes.any(
          {
            'quote',
            'locked',
            'jammer',
            'fico-image',
            'fico-thread',
            'showcontent',
            'tdpre',
            'aimg_tip',
            'tip_horn',
            'attach_nopermission',
            'attach_tips',
          }.contains,
        ) ||
        node.attributes.containsKey('hidden') ||
        node.attributes['aria-hidden'] == 'true' ||
        style.contains('display:none') ||
        style.contains('visibility:hidden') ||
        (!inline.contains(tag) && tag != 'p' && tag != 'div' && tag != 'br')) {
      valid = false;
      return;
    }
    if (tag == 'br') {
      out.writeln();
      return;
    }
    final paragraph = tag == 'p' || tag == 'div';
    if (paragraph && out.isNotEmpty) out.writeln();
    for (final child in node.nodes) {
      read(child);
    }
    if (paragraph) out.writeln();
  }

  read(element);
  return valid ? out.toString() : null;
}
