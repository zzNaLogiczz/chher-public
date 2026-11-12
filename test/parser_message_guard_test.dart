import 'package:chh_app/models/models.dart';
import 'package:chh_app/parser/forum_index_parser.dart';
import 'package:chh_app/parser/guide_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final parsers = <String, Object Function(String)>{
    'guide': parseGuide,
    'forum index': parseForumIndex,
  };
  for (final entry in parsers.entries) {
    for (final example in [
      ('站点维护中，请稍后重试', '', PageMessageKind.message),
      ('请先登录', '<div id="messagelogin"></div>', PageMessageKind.loginRequired),
      ('没有权限访问', '', PageMessageKind.permissionDenied),
    ]) {
      test(
        '${entry.key} preserves site messages instead of empty results: ${example.$3}',
        () {
          final html = '''<html><head><title>提示信息 - Chiphell</title></head>
<body><div id="messagetext">${example.$1}</div>${example.$2}</body></html>''';
          expect(
            () => entry.value(html),
            throwsA(
              isA<PageMessage>()
                  .having((m) => m.kind, 'kind', example.$3)
                  .having((m) => m.text, 'text', example.$1),
            ),
          );
        },
      );
    }
  }
}
