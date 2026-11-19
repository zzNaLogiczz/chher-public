final _displayParts = RegExp(
  r'(```[\s\S]*?```|``[^\r\n]*?``|`[^`\r\n]*`|'
  r'(?:[a-z][a-z\d+.-]*://|www\.|mailto:|(?:[a-z\d-]+\.)+[a-z]{2,}[/#?])'
  r'[^\s<>"“”，。！？；、]+|\b[a-z_$][\w$.]*\([^\r\n()]*\))|'
  r'(?<=\p{Script=Han})([,?!:;])(?=\p{Script=Han})|”|\.{3,}(?=\s*$)',
  caseSensitive: false,
  unicode: true,
);

const _fullWidth = {',': '，', '?': '？', '!': '！', ':': '：', ';': '；'};
final _newForumSuffix = RegExp(r'\s*[(（]新[)）]\s*$');

String formatForumName(String name) =>
    normalizeDisplayText(name.replaceFirst(_newForumSuffix, '').trimRight());

/// Display typography for headings and snippets. Keep the source text intact.
String normalizeDisplayText(String value) {
  final firstQuote = value.indexOf('”');
  final lastQuote = value.lastIndexOf('”');
  final repairQuote =
      firstQuote != lastQuote &&
      value.indexOf('”', firstQuote + 1) == lastQuote &&
      !value.contains('“');

  return value.replaceAllMapped(_displayParts, (match) {
    if (match[1] case final literal?) return literal;
    if (match[2] case final punctuation?) return _fullWidth[punctuation]!;
    if (match[0] == '”') {
      return repairQuote && match.start == firstQuote ? '“' : '”';
    }
    return '…';
  });
}
