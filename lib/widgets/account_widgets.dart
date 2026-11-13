/// Account surfaces share quiet grouping, clear touch targets and real data.
library;

import 'package:flutter/material.dart';
import '../design/icons.dart';
import '../design/motion.dart';
import '../design/shapes.dart';
import '../design/tokens.dart';
import '../ui/press.dart';
import '../design/typography.dart';
import 'avatar_image.dart';

/// 分组里的身份一行:头像 56、名字、UID,点进个人主页(或登录)
class AccountIdentityRow extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final String? detail;
  final VoidCallback? onTap;

  /// 压在漆面顶栏上(我的页身份卡):头像 54、奶白名字、淡朱 UID
  final bool onLac;
  const AccountIdentityRow({
    super.key,
    required this.name,
    this.avatarUrl,
    this.detail,
    this.onTap,
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
          AccountAvatar(url: avatarUrl, size: onLac ? 54 : 56),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
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
          if (onTap != null)
            Icon(AppIcons.forward, size: 13, color: onLac ? t.onLac3 : t.text3),
        ],
      ),
    );
    return onTap == null
        ? content
        : PressHighlight(onTap: onTap, semanticLabel: name, child: content);
  }
}

class AccountAvatar extends StatelessWidget {
  final String? url;
  final double size;

  final bool refreshable;
  const AccountAvatar({
    super.key,
    this.url,
    this.size = 72,
    this.refreshable = false,
  });
  @override
  Widget build(BuildContext context) =>
      AvatarImage(url: url, size: size, refreshable: refreshable);
}

/// 薄暮名片（方案 M-A）：24dp 主卡同心内嵌 18dp 浅雾槽（24 - 6 = 18），四柱无框轻盈陈列。
class MistyAccountHub extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final String? detail;
  final VoidCallback? onIdentityTap;
  final List<MistyAccountEntry> entries;

  const MistyAccountHub({
    super.key,
    required this.name,
    this.avatarUrl,
    this.detail,
    this.onIdentityTap,
    this.entries = const [],
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final columns = MediaQuery.textScalerOf(context).scale(1) >= 1.5 ? 2 : 4;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: t.surface,
        shape: appShape(AppRadii.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppClip(
              radius: AppRadii.md,
              child: PressHighlight(
                onTap: onIdentityTap,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
                  child: Row(
                    children: [
                      AccountAvatar(url: avatarUrl, size: 54),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: AppType.title2.copyWith(color: t.text),
                            ),
                            if (detail != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                detail!,
                                style: AppType.footnote.copyWith(color: t.text3),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (onIdentityTap != null) ...[
                        const SizedBox(width: 8),
                        Icon(AppIcons.forward, size: 14, color: t.text3),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (entries.isNotEmpty)
              DecoratedBox(
                decoration: ShapeDecoration(
                  color: t.mistyTray,
                  shape: appShape(AppRadii.md),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < entries.length; i += columns)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var j = i; j < i + columns; j++)
                              Expanded(
                                child: j < entries.length
                                    ? entries[j]
                                    : const SizedBox.shrink(),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class MistyAccountEntry extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final String label;
  final VoidCallback onTap;
  const MistyAccountEntry({
    super.key,
    required this.icon,
    required this.tint,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return AppClip(
      radius: AppRadii.sm,
      child: PressScale(
        onTap: onTap,
        semanticLabel: label,
        scale: .94,
        motion: AppMotion.entryTap,
        pressedColor: t.surface,
        child: ExcludeSemantics(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(2, 13, 2, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 22, color: tint),
                  const SizedBox(height: 7),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: AppType.footnote.copyWith(
                      color: t.text,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 工具图标使用与全站 IconTile 同规格的 30dp AppRadii.xs 超椭圆柔和色托。
class AccountToolWell extends StatelessWidget {
  final IconData icon;
  final bool accent;
  const AccountToolWell({super.key, required this.icon, this.accent = false});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: accent ? t.accentFill : t.fill,
        shape: appShape(AppRadii.xs),
      ),
      child: SizedBox.square(
        dimension: 30,
        child: Icon(icon, size: 17, color: accent ? t.accent : t.text2),
      ),
    );
  }
}

/// 漆面上的深漆凹槽:四列等宽入口,顶部内影与下沿细高光。
class LacEntryStrip extends StatelessWidget {
  final List<LacEntryCell> cells;
  const LacEntryStrip({super.key, required this.cells});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return AppClip(
      radius: AppRadii.md,
      child: ColoredBox(
        color: t.lacRecess,
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 3,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        t.lacRecessShade,
                        t.lacRecessShade.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(6),
              child: Row(
                children: [for (final cell in cells) Expanded(child: cell)],
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: AppSpace.hairline,
              child: IgnorePointer(
                child: ColoredBox(color: t.lacRecessHighlight),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 深漆入口:实心图标与奶白标签,按压缩放和填色共享手势与语义。
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
      scale: .94,
      motion: AppMotion.entryTap,
      pressedColor: t.onLac.withValues(alpha: .08),
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 22, color: t.onLac),
                const SizedBox(height: 9),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.footnote.copyWith(
                    color: t.onLac.withValues(alpha: .9),
                    fontWeight: FontWeight.w500,
                    letterSpacing: .3,
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
