final _envelope = RegExp(
  r'^\s*(?:<\?xml\s+[^<>]*\?>\s*)?<root>\s*<!\[CDATA\[([\s\S]*?)\]\]>\s*</root>\s*$',
);
final _userdata = RegExp(r"^\s*\{\s*'userdata'\s*:\s*\{([\s\S]*)\}\s*\}\s*$");
const _quotedValue = r"'(?:[^'\\]|\\[\s\S])*'";
// The bundled Discuz template omits the closing brace of individual rows.
final _row = RegExp(
  r"\s*[0-9]+\s*:\s*\{\s*'uid'\s*:\s*[0-9]+\s*,\s*'username'\s*:\s*"
  "$_quotedValue"
  r"\s*,\s*'avatar'\s*:\s*"
  "$_quotedValue"
  r"\s*,\s*'plid'\s*:\s*([0-9]+)\s*,\s*'isnew'\s*:\s*([0-9]+)\s*,"
  r"\s*'daterange'\s*:\s*[0-9]+\s*\}?\s*",
);

/// Parse the Discuz AJAX response. A malformed response is distinct from zero.
Set<String>? parseUnreadPmIds(String xml) {
  final payload = _envelope.firstMatch(xml)?.group(1);
  if (payload == null || payload.contains(']]>')) return null;
  final rows = _userdata.firstMatch(payload)?.group(1)?.trim();
  if (rows == null) return null;
  final unread = <String>{};
  var offset = 0;
  while (offset < rows.length) {
    final row = _row.matchAsPrefix(rows, offset);
    if (row == null) return null;
    final plid = row.group(1)!.replaceFirst(RegExp(r'^0+'), '');
    if (plid.isEmpty) return null;
    if (RegExp(r'[1-9]').hasMatch(row.group(2)!)) unread.add(plid);
    offset = row.end;
    if (offset == rows.length) break;
    if (rows[offset] != ',' || ++offset == rows.length) return null;
  }
  return unread;
}
