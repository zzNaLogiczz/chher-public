/// 设置类页面的分组零件:分组面、行、危险行、彩色图标、入口方块(规格 §6.6、§6.8)
library;

import 'package:flutter/material.dart';

import '../design/icons.dart';
import '../design/shapes.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import 'chrome_button.dart';
import 'press.dart';

/// 白色分组面:左右外边距 16,行间 0.5px 分隔线从文字起点开始
class GroupedSection extends StatelessWidget {
  final String? header;
  final String? headerTrailing;
  final String? footer;
  final List<Widget> children;

  const GroupedSection({
    super.key,
    this.header,
    this.headerTrailing,
    this.footer,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final caption = AppType.footnote.copyWith(
      color: t.text3,
      fontWeight: FontWeight.w600,
    );
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i < children.length - 1) {
        final child = children[i];
        rows.add(
          Padding(
            padding: EdgeInsets.only(
              left: child is GroupedRow
                  ? child.separatorInset
                  : AppSpace.rowInset,
            ),
            child: Divider(
              height: AppSpace.hairline,
              thickness: AppSpace.hairline,
              color: t.separator,
            ),
          ),
        );
      }
    }
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (header != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 7),
              child: Row(
                children: [
                  Expanded(child: Text(header!, style: caption)),
                  if (headerTrailing != null)
                    Text(headerTrailing!, style: caption),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.groupInset,
            ),
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: t.surface,
                shape: appShape(AppRadii.md),
              ),
              child: AppClip(
                radius: AppRadii.md,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: rows,
                ),
              ),
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 6, 32, 0),
              child: Text(
                footer!,
                style: AppType.footnote.copyWith(color: t.text3),
              ),
            ),
        ],
      ),
    );
  }
}

/// 分组里的一行。没有 onTap 时是只读行:无箭头、无按压反馈。
class GroupedRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? value;
  final Color? valueColor;
  final IconTile? icon;

  /// 自定义前置(头像、勋章图等),与 [icon] 二选一
  final Widget? leading;
  final VoidCallback? onTap;
  final bool? chevron;

  /// 箭头前的提示红点(如有新版本)
  final bool dot;

  const GroupedRow({
    super.key,
    required this.title,
    this.subtitle,
    this.value,
    this.valueColor,
    this.icon,
    this.leading,
    this.onTap,
    this.chevron,
    this.dot = false,
  });

  /// 分隔线从文字起点开始:有前置时跳过前置宽度
  double get separatorInset =>
      icon != null ? AppSpace.rowInset + IconTile.size + 12 : AppSpace.rowInset;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final lead = icon ?? leading;
    final titleColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: AppType.callout.copyWith(color: t.text)),
        if (subtitle != null)
          Text(subtitle!, style: AppType.footnote.copyWith(color: t.text3)),
      ],
    );
    final chevronIcon = [
      if (dot) ...[const SizedBox(width: 8), DotBadge(visible: dot)],
      if (chevron ?? onTap != null) ...[
        const SizedBox(width: 6),
        Icon(AppIcons.forward, size: 13, color: t.text3),
      ],
    ];
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.rowInset, 10, 12, 10),
        child: value == null
            ? Row(
                children: [
                  if (lead != null) ...[lead, const SizedBox(width: 12)],
                  Expanded(child: titleColumn),
                  ...chevronIcon,
                ],
              )
            // 键值行:标题按自身宽度排(最多 60%),值占满剩余空间并靠右
            : LayoutBuilder(
                builder: (context, constraints) => Row(
                  children: [
                    if (lead != null) ...[lead, const SizedBox(width: 12)],
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth * .6,
                      ),
                      child: titleColumn,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        value!,
                        textAlign: TextAlign.right,
                        style: AppType.subhead.copyWith(
                          color: valueColor ?? t.text3,
                        ),
                      ),
                    ),
                    ...chevronIcon,
                  ],
                ),
              ),
      ),
    );
    return onTap == null
        ? content
        : PressHighlight(onTap: onTap, semanticLabel: title, child: content);
  }
}

/// 危险操作:单独一组,居中红字,无箭头
class GroupedDestructiveRow extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const GroupedDestructiveRow({
    super.key,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return PressHighlight(
      onTap: onTap,
      semanticLabel: label,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Center(
          child: Text(
            label,
            style: AppType.callout.copyWith(
              color: t.red,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// 30dp 彩色小方块 + 白色线条图标,只用于设置类行
class IconTile extends StatelessWidget {
  static const double size = 30;
  final IconData icon;
  final Color tint;
  const IconTile({super.key, required this.icon, required this.tint});

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: tint,
      borderRadius: BorderRadius.circular(AppRadii.xs),
    ),
    child: SizedBox.square(
      dimension: size,
      child: Icon(icon, size: 17, color: Colors.white),
    ),
  );
}

/// "我的"页的入口方块:左上彩色图标,下方名称;按下弹性缩放
class EntryTile extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final String label;
  final VoidCallback? onTap;
  const EntryTile({
    super.key,
    required this.icon,
    required this.tint,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return PressScale(
      onTap: onTap,
      semanticLabel: label,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: t.surface,
          shape: appShape(AppRadii.md),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconTile(icon: icon, tint: tint),
              const SizedBox(height: 18),
              Text(
                label,
                style: AppType.subhead.copyWith(
                  color: t.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 入口方块两列排布;1.5 倍及以上字号改为单列,保证名称完整
class EntryGrid extends StatelessWidget {
  static const double _gap = 10;
  final List<EntryTile> tiles;
  const EntryGrid({super.key, required this.tiles});

  @override
  Widget build(BuildContext context) {
    final single = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final rows = <Widget>[];
    final perRow = single ? 1 : 2;
    for (var i = 0; i < tiles.length; i += perRow) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: _gap));
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var j = i; j < i + perRow; j++) ...[
                if (j > i) const SizedBox(width: _gap),
                Expanded(child: j < tiles.length ? tiles[j] : const SizedBox()),
              ],
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.groupInset),
      child: Column(mainAxisSize: MainAxisSize.min, children: rows),
    );
  }
}
