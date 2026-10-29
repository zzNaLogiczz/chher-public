/// 文字按钮:主按钮、次要、文字、危险四种,全部是胶囊(规格 §6.3)
///
/// 发送中、成功都在同一个胶囊里变形,不换按钮:文字缩小淡出 → 转圈 → 绿底对勾。
/// 文字始终留在布局里(只是透明),所以状态切换时宽度不会跳。
library;

import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import 'press.dart';

/// quiet:无底 text2 字,用于取消、回复这类次要文字操作(规格 §6.3)
enum AppButtonVariant { primary, tinted, plain, quiet, destructive }

enum AppButtonState { idle, busy, success }

class AppButton extends StatelessWidget {
  static const surfaceKey = ValueKey('app-button-surface');

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final bool small;
  final IconData? icon;
  final AppButtonState state;
  final bool trailingChevron;

  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.small = false,
    this.icon,
    this.state = AppButtonState.idle,
    this.trailingChevron = false,
  });

  bool get _filled =>
      variant == AppButtonVariant.primary || variant == AppButtonVariant.tinted;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final reduced = MediaQuery.disableAnimationsOf(context);
    final enabled = onPressed != null || state != AppButtonState.idle;
    final height = small ? 34.0 : 50.0;

    // 颜色:禁用一律 fill 底 + text3 字;其余按变体取令牌
    final Color? base = !_filled
        ? null
        : !enabled
        ? t.fill
        : variant == AppButtonVariant.primary
        ? t.accent
        : t.accentFill;
    final foreground = !enabled
        ? t.text3
        : switch (variant) {
            AppButtonVariant.primary => t.onAccent,
            AppButtonVariant.tinted || AppButtonVariant.plain => t.accent,
            AppButtonVariant.quiet => t.text2,
            AppButtonVariant.destructive => t.red,
          };
    final textStyle =
        (small ||
                    variant == AppButtonVariant.plain ||
                    variant == AppButtonVariant.quiet
                ? AppType.subhead.copyWith(fontWeight: FontWeight.w600)
                : variant == AppButtonVariant.destructive
                ? AppType.headline.copyWith(fontWeight: FontWeight.w500)
                : AppType.headline)
            .copyWith(color: foreground);

    final labelRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20, color: foreground),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textStyle,
          ),
        ),
        if (trailingChevron) ...[
          const SizedBox(width: 2),
          Icon(AppIcons.forward, size: 14, color: foreground),
        ],
      ],
    );

    final content = Stack(
      alignment: Alignment.center,
      children: [
        // 文字:空闲时可见,其余状态缩小淡出但保留宽度
        SingleMotionBuilder(
          value: state == AppButtonState.idle ? 1.0 : 0.0,
          motion: AppMotion.tap,
          active: !reduced,
          child: labelRow,
          builder: (_, v, child) => Opacity(
            opacity: v.clamp(0.0, 1.0),
            child: Transform.scale(scale: .8 + .2 * v, child: child),
          ),
        ),
        SingleMotionBuilder(
          value: state == AppButtonState.busy ? 1.0 : 0.0,
          motion: AppMotion.tap,
          active: !reduced,
          // 进入忙碌的那一帧就挂上转圈(随后淡入);退出时淡完才卸载
          builder: (_, v, _) => state != AppButtonState.busy && v <= 0.001
              ? const SizedBox.shrink()
              : Opacity(
                  opacity: v.clamp(0.0, 1.0),
                  child: SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: foreground,
                    ),
                  ),
                ),
        ),
        SingleMotionBuilder(
          value: state == AppButtonState.success ? 1.0 : 0.0,
          motion: AppMotion.pop,
          active: !reduced,
          builder: (_, v, _) => state != AppButtonState.success && v <= 0.001
              ? const SizedBox.shrink()
              : Transform.scale(
                  scale: v.clamp(0.0, 2.0),
                  child: Icon(
                    AppIcons.success,
                    size: 22,
                    color: _filled ? t.onAccent : t.green,
                  ),
                ),
        ),
      ],
    );

    final surface = SingleMotionBuilder(
      value: state == AppButtonState.success ? 1.0 : 0.0,
      motion: AppMotion.tap,
      active: !reduced,
      child: SizedBox(
        height: height,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: !_filled ? 6 : (small ? 16 : 24),
          ),
          child: Center(widthFactor: 1, child: content),
        ),
      ),
      builder: (_, v, child) => DecoratedBox(
        key: surfaceKey,
        decoration: BoxDecoration(
          color: base == null
              ? null
              : Color.lerp(base, t.green, v.clamp(0.0, 1.0)),
          borderRadius: BorderRadius.circular(height / 2),
        ),
        child: child,
      ),
    );

    return PressScale(
      onTap: state == AppButtonState.idle ? onPressed : null,
      semanticLabel: label,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Center(widthFactor: 1, heightFactor: 1, child: surface),
      ),
    );
  }
}
