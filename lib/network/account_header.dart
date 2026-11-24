import 'package:html/parser.dart' as html_parser;

final _htmlStart = RegExp(r'<html\b', caseSensitive: false);
final _htmlEnd = RegExp(r'</html\s*>', caseSensitive: false);
final _loginAction = RegExp(
  r'(?:^|/)member\.php\?mod=logging&action=login(?:&|$)',
  caseSensitive: false,
);

bool isGuestAccountDocument(String html) {
  final start = _htmlStart.firstMatch(html);
  if (start == null || !_htmlEnd.hasMatch(html.substring(start.end))) {
    return false;
  }
  final doc = html_parser.parse(html, generateSpans: true);
  final root = doc.documentElement;
  if (root?.sourceSpan == null ||
      root?.endSourceSpan == null ||
      doc.querySelector('#hd') == null ||
      doc.querySelector('#um, a[href*="action=logout"]') != null) {
    return false;
  }
  return doc
      .querySelectorAll('form')
      .any(
        (form) =>
            form.id == 'lsform' ||
            _loginAction.hasMatch(form.attributes['action'] ?? ''),
      );
}
