import 'package:flutter/widgets.dart';
import 'package:solar_icons/solar_icons.dart';

import 'tokens.dart';

// First match wins, in the order approved in forum-icons-2026-11-16/FINAL.md.
const _forumIconRules = [
  (keywords: ['归档'], icon: SolarIconsOutline.archiveDown),
  (keywords: ['举报'], icon: SolarIconsOutline.flag),
  (keywords: ['建议', '意见', '投诉'], icon: SolarIconsOutline.mailbox),
  (keywords: ['勋章'], icon: SolarIconsOutline.medalStar),
  (keywords: ['交易'], icon: SolarIconsOutline.tagPrice),
  (keywords: ['电脑', '硬件'], icon: SolarIconsOutline.cpuBolt),
  (keywords: ['新品', '纽斯'], icon: SolarIconsOutline.starsMinimalistic),
  (keywords: ['家居'], icon: SolarIconsOutline.sofa_2),
  (keywords: ['Blog', '博客'], icon: SolarIconsOutline.notebook),
  (keywords: ['赛'], icon: SolarIconsOutline.cupStar),
  (keywords: ['水世界'], icon: SolarIconsOutline.cupHot),
  (keywords: ['原创', '分享', '开箱'], icon: SolarIconsOutline.boxMinimalistic),
  (keywords: ['讨论'], icon: SolarIconsOutline.chatSquare),
];

/// Decorative icon derived only from the forum's current name.
IconData forumIconForName(String name) {
  for (final rule in _forumIconRules) {
    if (rule.keywords.any(name.contains)) return rule.icon;
  }
  return SolarIconsOutline.layersMinimalistic;
}

/// Shared title/description split for directory labels and category colors.
({String title, String? description}) forumCategoryName(String name) {
  final separator = RegExp(r'[-－—]').firstMatch(name);
  if (separator == null || separator.start == 0) {
    return (title: name, description: null);
  }
  final description = name.substring(separator.end).trim();
  return (
    title: name.substring(0, separator.start).trim(),
    description: description.isEmpty ? null : description,
  );
}

/// Category descriptions never determine the marker color.
Color forumCategoryTint(String name, AppTokens t) {
  final title = forumCategoryName(name).title;
  if (title.contains('讨论')) return t.tintDai;
  if (title.contains('互动')) return t.tintTan;
  if (title.contains('分享')) return t.tintCi;
  if (title.contains('站务')) return t.tintMo;
  return t.tintZhe;
}
