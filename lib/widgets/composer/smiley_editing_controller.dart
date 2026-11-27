import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/smiley_store.dart';
import '../../design/typography.dart';
import '../net_image.dart';

typedef VoiceTextRange = ({TextRange range, TextStyle style});

/// The editing value always contains the forum's source text in UTF-16 offsets.
class SmileyEditingController extends TextEditingController {
  SmileyEditingController({super.text});

  SmileyCatalog? catalog;
  List<VoiceTextRange> _voiceRanges = const [];

  void setVoiceTextRanges(List<VoiceTextRange> ranges, {bool notify = true}) {
    if (listEquals(_voiceRanges, ranges)) return;
    _voiceRanges = ranges;
    if (notify) notifyListeners();
  }

  TextInputFormatter? editingGuard;
  late final inputFormatter = TextInputFormatter.withFunction(
    (before, after) => _expandEdit(
      before,
      editingGuard?.formatEditUpdate(before, after) ?? after,
    ),
  );

  Iterable<RegExpMatch> _matches(String source) =>
      catalog?.codePattern.allMatches(source) ?? const [];

  @override
  set value(TextEditingValue next) {
    final before = value;
    // EditableText skips its formatters for composing-only updates.
    if (next.text == before.text && next.composing != before.composing) {
      next = editingGuard?.formatEditUpdate(before, next) ?? next;
    }
    final selection = next.selection;
    if (selection.isValid &&
        selection.end <= next.text.length &&
        next.composing.isCollapsed) {
      final previous = value.selection;
      var base = selection.baseOffset;
      var extent = selection.extentOffset;
      for (final match in _matches(next.text)) {
        if (match.start >= selection.end) break;
        if (selection.isCollapsed) {
          if (match.start < extent && extent < match.end) {
            // A one-step cursor movement from either edge skips the image.
            base = extent = switch (previous.extentOffset) {
              final offset when offset == match.start => match.end,
              final offset when offset == match.end => match.start,
              _ => match.end,
            };
          }
        } else {
          if (match.start < base && base < match.end) {
            base = selection.baseOffset == selection.start
                ? match.start
                : match.end;
          }
          if (match.start < extent && extent < match.end) {
            extent = selection.extentOffset == selection.start
                ? match.start
                : match.end;
          }
        }
      }
      next = next.copyWith(
        selection: selection.copyWith(baseOffset: base, extentOffset: extent),
      );
    }
    super.value = next;
  }

  TextSelection get _selectionOrEnd =>
      selection.isValid && selection.end <= text.length
      ? selection
      : TextSelection.collapsed(offset: text.length);

  void insertSmiley(SmileyEntry entry) {
    final selection = _selectionOrEnd;
    _replace(selection.start, selection.end, entry.code);
  }

  void deleteBeforeCursor() {
    final selection = _selectionOrEnd;
    if (!selection.isCollapsed) {
      _replace(selection.start, selection.end, '');
      return;
    }
    final end = selection.end;
    if (end == 0) return;
    final start = end - text.substring(0, end).characters.last.length;
    _replace(start, end, '');
  }

  void _replace(int start, int end, String replacement) {
    final next = TextEditingValue(
      text: text.replaceRange(start, end, replacement),
      selection: TextSelection.collapsed(offset: start + replacement.length),
    );
    value = _expandEdit(value, next);
  }

  /// Both the platform IME and the panel can request a partial removal.
  TextEditingValue _expandEdit(TextEditingValue before, TextEditingValue next) {
    if (!before.composing.isCollapsed ||
        !next.composing.isCollapsed ||
        before.text == next.text ||
        catalog == null) {
      return next;
    }

    final oldText = before.text;
    final newText = next.text;
    var start = 0;
    var oldEnd = oldText.length;
    var newEnd = newText.length;
    // A collapsed caret after a replacement bounds the changed prefix even
    // when adjacent text happens to repeat the deleted characters.
    final limit = next.selection.isValid && next.selection.isCollapsed
        ? next.selection.end
        : newEnd;
    while (start < oldEnd &&
        start < newEnd &&
        start < limit &&
        oldText.codeUnitAt(start) == newText.codeUnitAt(start)) {
      start++;
    }
    while (oldEnd > start &&
        newEnd > start &&
        newEnd > limit &&
        oldText.codeUnitAt(oldEnd - 1) == newText.codeUnitAt(newEnd - 1)) {
      oldEnd--;
      newEnd--;
    }
    if (oldEnd == start) return next;

    var replaceStart = start;
    var replaceEnd = oldEnd;
    for (final match in _matches(oldText)) {
      if (match.start >= oldEnd) break;
      if (match.end <= start) continue;
      if (match.start < replaceStart) replaceStart = match.start;
      if (match.end > replaceEnd) replaceEnd = match.end;
    }
    if (replaceStart == start && replaceEnd == oldEnd) return next;

    final replacement = newText.substring(start, newEnd);
    return next.copyWith(
      text: oldText.replaceRange(replaceStart, replaceEnd, replacement),
      selection: TextSelection.collapsed(
        offset: replaceStart + replacement.length,
      ),
    );
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final catalog = this.catalog;
    if ((catalog == null && _voiceRanges.isEmpty) || text.isEmpty) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    final composing = withComposing && value.isComposingRangeValid
        ? value.composing
        : TextRange.empty;
    final children = <InlineSpan>[];
    void addPlainText(int start, int end, [TextStyle? voiceStyle]) {
      if (start == end) return;
      if (composing.isCollapsed ||
          composing.end <= start ||
          composing.start >= end) {
        children.add(
          TextSpan(text: text.substring(start, end), style: voiceStyle),
        );
        return;
      }
      final from = composing.start.clamp(start, end);
      final to = composing.end.clamp(start, end);
      if (from > start) {
        children.add(
          TextSpan(text: text.substring(start, from), style: voiceStyle),
        );
      }
      children.add(
        TextSpan(
          text: text.substring(from, to),
          style: (voiceStyle ?? const TextStyle()).copyWith(
            decoration: TextDecoration.underline,
          ),
        ),
      );
      if (to < end) {
        children.add(
          TextSpan(text: text.substring(to, end), style: voiceStyle),
        );
      }
    }

    void addText(int start, int end) {
      for (final (:range, :style) in _voiceRanges) {
        if (range.end <= start) continue;
        if (range.start >= end) break;
        final from = range.start.clamp(start, end);
        final to = range.end.clamp(from, end);
        addPlainText(start, from);
        addPlainText(from, to, style);
        start = to;
      }
      addPlainText(start, end);
    }

    final size = style?.fontSize ?? AppType.sizeBody;
    var start = 0;
    for (final match in _matches(text)) {
      if (!composing.isCollapsed &&
          composing.start < match.end &&
          composing.end > match.start) {
        continue;
      }
      if (_voiceRanges.any(
        (voice) =>
            voice.range.start < match.end && voice.range.end > match.start,
      )) {
        continue;
      }
      addText(start, match.start);
      final entry = catalog!.byCode[match.group(0)]!;
      children.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: NetImage(
            url: entry.url,
            width: size,
            height: size,
            fit: BoxFit.contain,
          ),
        ),
      );
      // WidgetSpan consumes one UTF-16 offset. Invisible word joiners keep
      // RenderEditable's positions aligned with the rest of the raw value.
      if (entry.code.length > 1) {
        children.add(TextSpan(text: '\u2060' * (entry.code.length - 1)));
      }
      start = match.end;
    }
    addText(start, text.length);
    return TextSpan(style: style, children: children);
  }
}
