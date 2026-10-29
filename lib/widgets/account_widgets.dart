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
  const AccountIdentityRow({
    super.key,
    required this.name,
    this.avatarUrl,
    this.detail,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.rowInset, 12, 12, 12),
      child: Row(
        children: [
          AccountAvatar(url: avatarUrl, size: 56),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name, style: AppType.title2.copyWith(color: t.text)),
                if (detail != null)
                  Text(
                    detail!,
                    style: AppType.footnote.copyWith(color: t.text3),
                  ),
              ],
            ),
          ),
          if (onTap != null) Icon(AppIcons.forward, size: 13, color: t.text3),
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
  const AccountAvatar({super.key, this.url, this.size = 72});
  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: url == null
            ? ColoredBox(
                color: t.fill,
                child: Icon(AppIcons.person, size: size * .45, color: t.text2),
              )
            : NetImage(url: url!, width: size, height: size),
      ),
    );
  }
}
