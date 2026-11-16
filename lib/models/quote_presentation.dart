import 'models.dart';

final _signature = RegExp(
  r'^(.+?)\s*发表于\s+(\d{4}-\d{1,2}-\d{1,2}\s+\d{1,2}:\d{2}(?::\d{2})?)(?![\d:])',
);

/// Presentation only: never change the parsed reference or inference evidence.
QuoteBlock quoteForDisplay(QuoteBlock quote) {
  final source = quote.source?.trim();
  if (source == null) return quote;
  final signature = _signature.firstMatch(source);
  if (signature == null || !_validTime(signature[2]!)) return quote;
  final author = signature[1]!.trim();
  if (author.isEmpty) return quote;
  final prefix = RegExp(
    '^\\s*${signature[0]!.trim().split(RegExp(r'\s+')).map(RegExp.escape).join(r'\s+')}(?:\\s+|\$)',
  );
  var children = quote.children;
  if (children.isNotEmpty && children.first is TextBlock) {
    final first = children.first as TextBlock;
    final match = prefix.firstMatch(first.text);
    if (match != null) {
      final nodes = first.hasInline
          ? _stripNodes(first.nodes, prefix)
          : const <InlineNode>[];
      // A smiley or different inline text before the signature is not a header.
      if (nodes != null) {
        final text = first.text.substring(match.end);
        children = [
          if (text.isNotEmpty || nodes.isNotEmpty)
            TextBlock(text, nodes: nodes),
          ...children.skip(1),
        ];
      }
    }
  }
  return QuoteBlock(
    children,
    source: author,
    reference: quote.reference,
    unlinkedEvidence: quote.unlinkedEvidence,
    isNotice: quote.isNotice,
  );
}

bool _validTime(String time) {
  final parts = RegExp(
    r'\d+',
  ).allMatches(time).map((m) => int.parse(m[0]!)).toList();
  final second = parts.length == 6 ? parts[5] : 0;
  final date = DateTime(
    parts[0],
    parts[1],
    parts[2],
    parts[3],
    parts[4],
    second,
  );
  return date.year == parts[0] &&
      date.month == parts[1] &&
      date.day == parts[2] &&
      date.hour == parts[3] &&
      date.minute == parts[4] &&
      date.second == second;
}

List<InlineNode>? _stripNodes(List<InlineNode> nodes, RegExp prefix) {
  final raw = nodes
      .map(
        (node) => switch (node) {
          InlineText(:final text) || InlineLink(:final text) => text,
          InlineSmiley() => '\uFFFC',
        },
      )
      .join();
  final match = prefix.firstMatch(raw);
  if (match == null) return null;
  var remaining = match.end;
  final result = <InlineNode>[];
  for (final node in nodes) {
    if (remaining == 0) {
      result.add(node);
      continue;
    }
    final text = switch (node) {
      InlineText(:final text) || InlineLink(:final text) => text,
      InlineSmiley() => '\uFFFC',
    };
    if (text.length <= remaining) {
      remaining -= text.length;
    } else {
      final tail = text.substring(remaining);
      result.add(switch (node) {
        InlineLink(:final target) => InlineLink(tail, target),
        _ => InlineText(tail),
      });
      remaining = 0;
    }
  }
  return result;
}
