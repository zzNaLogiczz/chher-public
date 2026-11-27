import 'dart:io';

import '../core/app_paths.dart';
import '../core/chh_urls.dart';
import '../di.dart';
import '../network/chh_client.dart';

final smileyStore = SmileyStore(chhClient);

class SmileyEntry {
  final String code;
  final String url;

  const SmileyEntry(this.code, this.url);
}

class SmileyGroup {
  final String name;
  final List<SmileyEntry> entries;

  SmileyGroup._(this.name, List<SmileyEntry> entries)
    : entries = List.unmodifiable(entries);
}

class SmileyCatalog {
  final List<SmileyGroup> groups;
  final Map<String, SmileyEntry> byCode;
  final RegExp codePattern;

  SmileyCatalog._(List<SmileyGroup> groups, Map<String, SmileyEntry> entries)
    : groups = List.unmodifiable(groups),
      byCode = Map.unmodifiable(entries),
      codePattern = RegExp(
        (entries.keys.toList()..sort((a, b) => b.length.compareTo(a.length)))
            .map(RegExp.escape)
            .join('|'),
      );

  static const _string =
      r'''(?:'(?:[^'\\]|\\[\s\S])*'|"(?:[^"\\]|\\[\s\S])*")''';
  static const _row = '''\\[(?:$_string|[^\\[\\]'"])*\\]''';
  static final _types = RegExp(
    r'''\bsmilies_type\s*\[\s*['"]_(\d+)['"]\s*\]\s*=\s*\['''
    '\\s*($_string)\\s*,\\s*($_string)'
    r'\s*,?\s*\]',
  );
  static final _pages = RegExp(
    r'''\bsmilies_array\s*\[\s*['"]?(\d+)['"]?\s*\]'''
    r'''\s*\[\s*['"]?(\d+)['"]?\s*\]\s*=\s*\['''
    '''((?:$_row|[^\\[\\]'"])*)'''
    r'\]',
  );
  static final _rows = RegExp(_row);
  static final _entry = RegExp(
    r'''\[\s*(?:'\d+'|"\d+"|\d+)\s*,'''
    '\\s*($_string)\\s*,\\s*($_string)'
    r'\s*(?:,|\])',
  );
  static final _escapes = RegExp(
    r'\\(u[\da-fA-F]{4}|x[\da-fA-F]{2}|\r\n|[\s\S])',
  );
  static final _invalidSegmentChars = RegExp(r'[/\\\x00-\x1f]');

  static String _decode(String literal) => literal
      .substring(1, literal.length - 1)
      .replaceAllMapped(_escapes, (match) {
        final escape = match[1]!;
        if (escape.length > 1 && escape != '\r\n') {
          return String.fromCharCode(int.parse(escape.substring(1), radix: 16));
        }
        return switch (escape) {
          'n' => '\n',
          'r' => '\r',
          't' => '\t',
          'b' => '\b',
          'f' => '\f',
          'v' => '\v',
          '0' => '\x00',
          '\r\n' || '\r' || '\n' => '',
          _ => escape,
        };
      });

  static bool _validSegment(String value) =>
      value.isNotEmpty &&
      value != '.' &&
      value != '..' &&
      !value.contains(_invalidSegmentChars);

  /// Discuz emits one assignment per group and one per page of entries.
  static SmileyCatalog parse(String source, {Uri? siteBase}) {
    final pages = <String, Map<int, String>>{};
    for (final page in _pages.allMatches(source)) {
      final index = int.tryParse(page[2]!);
      if (index != null) (pages[page[1]!] ??= {})[index] = page[3]!;
    }

    final base = siteBase ?? Uri.parse(ChhUrls.base);
    final groups = <SmileyGroup>[];
    final byCode = <String, SmileyEntry>{};
    for (final type in _types.allMatches(source)) {
      final typePages = pages[type[1]!];
      final name = _decode(type[2]!);
      final directory = _decode(type[3]!);
      if (typePages == null || name.isEmpty || !_validSegment(directory)) {
        continue;
      }
      final entries = <SmileyEntry>[];
      for (final index in typePages.keys.toList()..sort()) {
        for (final row in _rows.allMatches(typePages[index]!)) {
          final match = _entry.matchAsPrefix(row[0]!);
          if (match == null) continue;
          final code = _decode(match[1]!);
          final filename = _decode(match[2]!);
          if (code.isEmpty || !_validSegment(filename)) continue;
          final url = base.replace(
            pathSegments: ['static', 'image', 'smiley', directory, filename],
          );
          final entry = SmileyEntry(code, url.toString());
          entries.add(entry);
          byCode.putIfAbsent(code, () => entry);
        }
      }
      if (entries.isNotEmpty) groups.add(SmileyGroup._(name, entries));
    }
    if (groups.isEmpty) throw const FormatException('表情数据无效');
    return SmileyCatalog._(groups, byCode);
  }
}

class SmileyStore {
  final ChhClient _client;
  final File? _cacheFile;
  final Uri _siteBase;
  SmileyCatalog? _catalog;
  Future<SmileyCatalog?>? _reading;
  Future<SmileyCatalog>? _loading;

  SmileyStore(this._client, {this._cacheFile, Uri? siteBase})
    : _siteBase = siteBase ?? Uri.parse(ChhUrls.base);

  static const _sourcePath = '/data/cache/common_smilies_var.js';

  Future<File?> _file() async {
    if (_cacheFile != null) return _cacheFile;
    final directory = await AppPaths.instance.subdir('smilies');
    return directory == null ? null : File('${directory.path}/catalog.js');
  }

  /// Restore images in saved drafts without fetching anything on editor open.
  Future<SmileyCatalog?> readCache() async =>
      _catalog ?? await (_reading ??= _read());

  Future<SmileyCatalog?> _read() async {
    try {
      final file = await _file();
      if (file == null) return null;
      final source = await file.readAsString();
      return _catalog = SmileyCatalog.parse(source, siteBase: _siteBase);
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  Future<SmileyCatalog> load() =>
      _loading ??= _load().whenComplete(() => _loading = null);

  Future<SmileyCatalog> _load() async {
    final cached = await readCache();
    if (cached != null) return cached;
    // The WebView's AJAX transport reads raw text without navigating to the JS.
    final source = await _client.getAjaxHtml(
      _siteBase.resolve(_sourcePath),
      refresh: true,
    );
    final catalog = SmileyCatalog.parse(source, siteBase: _siteBase);
    try {
      final file = await _file();
      if (file != null) {
        await file.parent.create(recursive: true);
        final temporary = File('${file.path}.tmp');
        await temporary.writeAsString(source, flush: true);
        await temporary.rename(file.path);
      }
    } on FileSystemException {
      // The current session can still use the catalog when storage is full.
    }
    return _catalog = catalog;
  }
}
