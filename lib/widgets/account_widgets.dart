/// Account surfaces share quiet grouping, clear touch targets and real data.
library;

import 'package:flutter/material.dart';
import '../design/icons.dart';
import '../design/motion.dart';
import '../design/shapes.dart';
import '../design/tokens.dart';
import '../ui/grouped.dart';
import '../ui/press.dart';
import '../design/typography.dart';
import 'avatar_image.dart';

/// 分组里的身份一行:头像 56、名字、UID,点进个人主页(或登录)
class AccountIdentityRow extends StatelessWidget {
  final String name;
  final Widget? title;
  final String? avatarUrl;
  final String? detail;
  final VoidCallback? onTap;
  final Widget? trailing;

  /// 压在漆面顶栏上(我的页身份卡):头像 54、奶白名字、淡朱 UID
  final bool onLac;
  const AccountIdentityRow({
    super.key,
    required this.name,
    this.title,
    this.avatarUrl,
    this.detail,
    this.onTap,
    this.trailing,
    this.onLac = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final content = Padding(
      padding: onLac
          ? const EdgeInsets.fromLTRB(AppSpace.screen, 8, 12, 4)
          : const EdgeInsets.fromLTRB(AppSpace.rowInset, 12, 12, 12),
      child: Row(
        children: [
          AccountAvatar(name: name, url: avatarUrl, size: onLac ? 54 : 56),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                title ??
                    Text(
                      name,
                      style: onLac
                          ? AppType.title1.copyWith(color: t.onLac)
                          : AppType.title2.copyWith(color: t.text),
                    ),
                if (detail != null)
                  Text(
                    detail!,
                    style: AppType.footnote.copyWith(
                      color: onLac ? t.onLac2 : t.text3,
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null)
            trailing!
          else if (onTap != null)
            Icon(AppIcons.forward, size: 13, color: onLac ? t.onLac3 : t.text3),
        ],
      ),
    );
    return onTap == null
        ? content
        : PressHighlight(
            onTap: onTap,
            semanticLabel: title == null ? name : '主页',
            child: content,
          );
  }
}

class AccountAvatar extends StatelessWidget {
  final String? url;
  final String name;
  final double size;

  final bool refreshable;
  const AccountAvatar({
    super.key,
    this.url,
    this.name = '',
    this.size = 72,
    this.refreshable = false,
  });
  @override
  Widget build(BuildContext context) =>
      AvatarImage(name: name, url: url, size: size, refreshable: refreshable);
}

/// 跨接缝的入口浮卡；大字号改成两列，完整保留入口标签。
class LacEntryStrip extends StatelessWidget {
  final List<LacEntryCell> cells;
  const LacEntryStrip({super.key, required this.cells});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final columns = largeText ? 2 : (cells.length == 5 ? 5 : 4);
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: t.surface,
        shape: appShape(MeTokens.cardRadius),
        shadows: t.style == AppearanceStyle.misty
            ? MeTokens.cardShadow(t)
            : MeTokens.floatingShadow(t),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < cells.length; i += columns)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var j = i; j < i + columns; j++)
                    Expanded(
                      child: j < cells.length
                          ? cells[j]
                          : const SizedBox.shrink(),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class LacEntryCell extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const LacEntryCell({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return PressScale(
      onTap: onTap,
      semanticLabel: label,
      scale: AppPressScale.control,
      motion: AppMotion.entryTap,
      pressedColor: t.pressed,
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(2, 6, 2, 5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconTile(icon: icon),
                const SizedBox(height: 6),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: AppType.footnote.copyWith(
                    fontSize: MeTokens.entryLabel,
                    color: t.text.withValues(alpha: .86),
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
