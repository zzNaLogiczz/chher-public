/// 分区标题:title2 + 右侧"全部 ›"或自定义控件(紧凑分段),左右 20(规格 §6.8 精选)
library;

import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../design/typography.dart';
import 'app_button.dart';

class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? trailing;

  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.screen,
        AppSpace.section,
        AppSpace.screen - 6,
        8,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: AppType.title2.copyWith(color: t.text)),
          ),
          if (trailing != null)
            Padding(padding: const EdgeInsets.only(right: 6), child: trailing!)
          else if (actionLabel != null)
            AppButton(
              label: actionLabel!,
              variant: AppButtonVariant.plain,
              trailingChevron: true,
              onPressed: onAction,
            ),
        ],
      ),
    );
  }
}
