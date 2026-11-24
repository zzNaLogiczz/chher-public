import 'package:chh_app/data/pm_unread.dart';
import 'package:flutter_test/flutter_test.dart';

String xml(String payload) =>
    '<?xml version="1.0" encoding="utf-8"?>\n<root><![CDATA[\n$payload\n]]></root>';

String row(
  int uid,
  int plid,
  int isnew, {
  String username = 'fixture',
  String end = '}',
}) =>
    "$uid:{'uid':$uid, 'username':'$username', 'avatar':'/avatar', "
    "'plid':$plid, 'isnew':$isnew, 'daterange':1$end";

String payload(List<String> rows) {
  final users = rows.join(',');
  return "{'userdata':{$users}}";
}

void main() {
  test(
    'collects distinct unread conversation IDs and handles escaped names',
    () {
      final rows = [
        row(10, 100, 3, username: r"O\'Brien\\test"),
        row(20, 200, 0),
        row(30, 100, 1),
        row(40, 400, 2),
      ];
      expect(parseUnreadPmIds(xml(payload(rows))), {'100', '400'});
    },
  );

  test('also accepts the bundled Discuz template with unclosed rows', () {
    final rows = [row(10, 100, 3, end: ''), row(20, 200, 0, end: '')];
    expect(parseUnreadPmIds(xml(payload(rows))), {'100'});
  });

  test('distinguishes known zero from unrecognized responses', () {
    expect(parseUnreadPmIds(xml(payload([row(10, 100, 0)]))), isEmpty);
    expect(parseUnreadPmIds(xml(payload([]))), isEmpty);
    expect(parseUnreadPmIds(xml('<div>请先登录后继续</div>')), isNull);
    expect(parseUnreadPmIds(payload([])), isNull);
    expect(parseUnreadPmIds(xml("{'userdata':null}")), isNull);
    expect(parseUnreadPmIds(xml(payload([row(10, 100, 1), 'broken']))), isNull);
    expect(parseUnreadPmIds(xml(payload([row(10, 0, 1)]))), isNull);
    expect(
      parseUnreadPmIds(xml(payload([row(10, 100, 1, username: ']]>')]))),
      isNull,
    );
  });
}
