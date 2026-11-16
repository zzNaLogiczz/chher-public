import 'package:chh_app/design/forum_icons.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solar_icons/solar_icons.dart';

void main() {
  const realForums = {
    '交易区': SolarIconsOutline.tagPrice,
    '自由水世界2024': SolarIconsOutline.cupHot,
    '勋章申请区': SolarIconsOutline.medalStar,
    'iGame Mini 桌搭”小钢炮”装机赛': SolarIconsOutline.cupStar,
    '大恶魔的Blog': SolarIconsOutline.notebook,
    '原创分享(新)': SolarIconsOutline.boxMinimalistic,
    '家居': SolarIconsOutline.sofa_2,
    '相关讨论': SolarIconsOutline.chatSquare,
    '电脑讨论(新)': SolarIconsOutline.cpuBolt,
    '新品”纽斯”': SolarIconsOutline.starsMinimalistic,
    '建议意见及投诉': SolarIconsOutline.mailbox,
    '举报专区': SolarIconsOutline.flag,
    '活动区归档': SolarIconsOutline.archiveDown,
  };
  for (final entry in realForums.entries) {
    test('real forum ${entry.key} uses its approved icon', () {
      expect(forumIconForName(entry.key), entry.value);
    });
  }

  const renamedForums = {
    '自由水世界2025': SolarIconsOutline.cupHot,
    '2027 桌搭装机赛': SolarIconsOutline.cupStar,
    '活动区归档': SolarIconsOutline.archiveDown,
    '电脑讨论(新)': SolarIconsOutline.cpuBolt,
    '水冷散热': SolarIconsOutline.layersMinimalistic,
    '摄影': SolarIconsOutline.layersMinimalistic,
    '': SolarIconsOutline.layersMinimalistic,
  };
  for (final entry in renamedForums.entries) {
    test('renamed or new forum ${entry.key} follows keyword rules', () {
      expect(forumIconForName(entry.key), entry.value);
    });
  }

  const aliases = {
    '建议': SolarIconsOutline.mailbox,
    '意见': SolarIconsOutline.mailbox,
    '投诉': SolarIconsOutline.mailbox,
    '硬件': SolarIconsOutline.cpuBolt,
    '纽斯': SolarIconsOutline.starsMinimalistic,
    '博客': SolarIconsOutline.notebook,
    '分享': SolarIconsOutline.boxMinimalistic,
    '开箱': SolarIconsOutline.boxMinimalistic,
  };
  for (final entry in aliases.entries) {
    test('alternate keyword ${entry.key} is recognized', () {
      expect(forumIconForName(entry.key), entry.value);
    });
  }

  test('the first matching rule wins throughout the approved order', () {
    const ordered = {
      '归档': SolarIconsOutline.archiveDown,
      '举报': SolarIconsOutline.flag,
      '建议': SolarIconsOutline.mailbox,
      '勋章': SolarIconsOutline.medalStar,
      '交易': SolarIconsOutline.tagPrice,
      '电脑': SolarIconsOutline.cpuBolt,
      '新品': SolarIconsOutline.starsMinimalistic,
      '家居': SolarIconsOutline.sofa_2,
      'Blog': SolarIconsOutline.notebook,
      '赛': SolarIconsOutline.cupStar,
      '水世界': SolarIconsOutline.cupHot,
      '原创': SolarIconsOutline.boxMinimalistic,
      '讨论': SolarIconsOutline.chatSquare,
    };
    final entries = ordered.entries.toList();
    for (var i = 0; i < entries.length - 1; i++) {
      expect(
        forumIconForName('${entries[i + 1].key}${entries[i].key}'),
        entries[i].value,
      );
    }
  });

  test('category title splitting preserves the directory label rules', () {
    for (final separator in ['-', '－', '—']) {
      expect(forumCategoryName(' 数码区 $separator 讨论与分享 '), (
        title: '数码区',
        description: '讨论与分享',
      ));
      expect(forumCategoryName('讨论区 $separator '), (
        title: '讨论区',
        description: null,
      ));
      expect(forumCategoryName('$separator讨论区'), (
        title: '$separator讨论区',
        description: null,
      ));
    }
    expect(forumCategoryName('未知分区'), (title: '未知分区', description: null));
  });

  for (final t in [
    AppTokens.cinnabarLight,
    AppTokens.cinnabarDark,
    AppTokens.mistyLight,
    AppTokens.mistyDark,
  ]) {
    test('${t.style} dark=${t.isDark} uses only category title tint slots', () {
      final cases = {
        '讨论区': t.tintDai,
        '互动区': t.tintTan,
        '分享区': t.tintCi,
        '站务区': t.tintMo,
        '未知分区': t.tintZhe,
        '收藏': t.tintZhe,
        '': t.tintZhe,
      };
      for (final entry in cases.entries) {
        expect(forumCategoryTint(entry.key, t), entry.value);
        expect(forumCategoryTint(entry.key, t), isNot(t.tintZhu));
      }
      for (final separator in ['-', '－', '—']) {
        expect(forumCategoryTint('数码区 $separator 讨论与分享', t), t.tintZhe);
        expect(forumCategoryTint('互动区 $separator 讨论与分享', t), t.tintTan);
        expect(forumCategoryTint('分享区 $separator 站务与互动', t), t.tintCi);
        expect(forumCategoryTint('站务区 $separator 讨论与互动', t), t.tintMo);
      }
    });
  }
}
