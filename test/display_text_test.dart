import 'package:chh_app/design/display_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('D3 converts halfwidth punctuation only between Han characters', () {
    expect(normalizeDisplayText('甲,乙?丙!丁:戊;己，𠮷,野'), '甲，乙？丙！丁：戊；己，𠮷，野');
    const mixed = '芯片:CPU, GPU! 甲, 乙; 3.14 青,2026年？真的嗎?';
    expect(normalizeDisplayText(mixed), mixed);
  });

  test('D3 repairs only a pair of right quotes with no left quote', () {
    expect(normalizeDisplayText('桌搭”小钢炮”装机赛'), '桌搭“小钢炮”装机赛');
    for (final text in ['桌搭”', '桌搭“小钢炮”', '桌搭”小钢炮”蓝”']) {
      expect(normalizeDisplayText(text), text);
    }
  });

  test('D3 preserves code and URL contents', () {
    expect(
      normalizeDisplayText(
        '甲,乙 `函数(甲,乙)””` show(甲,乙) https://example.com/甲,乙?丙...',
      ),
      '甲，乙 `函数(甲,乙)””` show(甲,乙) https://example.com/甲,乙?丙...',
    );
    const code = '```\n甲,乙 `丙;丁` 戊!己\n``` example.com/甲,乙';
    expect(normalizeDisplayText(code), code);
  });

  test('D2 normalizes a trailing dot run to one ellipsis', () {
    expect(normalizeDisplayText('坚持...'), '坚持…');
    expect(normalizeDisplayText('坚持....  '), '坚持…  ');
    expect(normalizeDisplayText('前面...后面..'), '前面...后面..');
    expect(normalizeDisplayText('继续…'), '继续…');
  });
}
