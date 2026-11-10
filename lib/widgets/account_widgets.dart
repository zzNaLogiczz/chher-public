/// Account surfaces share quiet grouping, clear touch targets and real data.
library;

import 'package:flutter/material.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../ui/press.dart';
import '../design/typography.dart';
import 'net_image.dart';
import 'expressive_controls.dart';

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
          AccountAvatar(
            url: avatarUrl,
            size: onLac ? 54 : 56,
            placeholderColor: onLac
                ? const Color.fromRGBO(255, 248, 245, .18)
                : null,
            placeholderIconColor: onLac ? t.onLac : null,
          ),
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

  /// 漆面上占位头像的底色与图标色;缺省用纸面 fill/text2
  final Color? placeholderColor;
  final Color? placeholderIconColor;
  const AccountAvatar({
    super.key,
    this.url,
    this.size = 72,
    this.placeholderColor,
    this.placeholderIconColor,
  });
  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: url == null
            ? ColoredBox(
                color: placeholderColor ?? t.fill,
                child: Icon(
                  AppIcons.person,
                  size: size * .45,
                  color: placeholderIconColor ?? t.text2,
                ),
              )
            : NetImage(url: url!, width: size, height: size),
      ),
    );
  }
}

/// “我的”页定稿入口行:无卡片、无底色,直接排在纸面上的四列。
/// 国色线形图标 + 13px 标签 + 细竖线分隔;颜色只留在图标上。
class EntryRow extends StatelessWidget {
  final List<EntryCell> cells;
  const EntryRow({super.key, required this.cells});

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    // 1.5 倍及以上字号退成两列,保证标签完整
    final perRow = scaler.scale(1) >= 1.5 ? 2 : 4;
    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += perRow) {
      final slice = [
        for (var j = i; j < (i + perRow).clamp(0, cells.length); j++) cells[j],
      ];
      rows.add(
        Row(
          children: [
            for (var k = 0; k < slice.length; k++) ...[
              if (k > 0)
                Container(
                  width: AppSpace.hairline,
                  height: 34,
                  color: AppTokens.of(context).separator,
                ),
              Expanded(child: slice[k]),
            ],
          ],
        ),
      );
      if (i + perRow < cells.length) rows.add(const SizedBox(height: 14));
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
      child: Column(children: rows),
    );
  }
}

/// [EntryRow] 的一格:图标 24 加小标签,整格可点
class EntryCell extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final String label;
  final VoidCallback? onTap;
  const EntryCell({
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
      scale: .94,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 24, child: Icon(icon, size: 24, color: tint)),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.footnote.copyWith(
                color: t.text2,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
