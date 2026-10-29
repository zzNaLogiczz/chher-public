import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 页面与通用组件只能用 lib/design 的令牌和 lib/ui 的零件(规格 §10.3)。
/// 确有理由的例外写进 test/design_guard_allowlist.txt,上一行用 # 注明原因。
final rules = <String, RegExp>{
  'raw fontSize': RegExp(r'fontSize:\s*\d'),
  'raw radius': RegExp(r'BorderRadius\.circular\(\s*\d'),
  'raw duration': RegExp(r'Duration\(milliseconds'),
  'raw shadow': RegExp(r'BoxShadow\('),
  'raw color': RegExp(r'Color\(0x'),
  'Colors.*': RegExp(r'\bColors\.(?!transparent\b)'),
  'material buttons': RegExp(
    r'\b(TextButton|FilledButton|OutlinedButton|InkWell)(\.icon)?\(',
  ),
  'blur': RegExp(r'BackdropFilter\('),
};

void main() {
  test('pages and widgets only use design tokens and ui parts', () {
    final allow = File('test/design_guard_allowlist.txt')
        .readAsLinesSync()
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('#'))
        .toSet();
    final hits = <String>[];
    for (final dir in ['lib/pages', 'lib/widgets']) {
      final files =
          Directory(dir)
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      for (final f in files) {
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          for (final rule in rules.entries) {
            if (!rule.value.hasMatch(lines[i])) continue;
            final key = '${f.path}:${rule.key}:${lines[i].trim()}';
            if (!allow.contains(key)) hits.add(key);
          }
        }
      }
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });
}
