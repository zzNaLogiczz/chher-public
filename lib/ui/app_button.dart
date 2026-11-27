/// 共享文字按钮，包含编辑器专用的发送胶囊。
///
/// 发送中、成功都在同一个胶囊里变形,不换按钮:文字缩小淡出 → C 字加载标记 → 绿底对勾。
/// 发送胶囊跟随当前标签宽度，其他变体沿用既有布局。
library;

import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

import '../design/composer_tokens.dart';
import '../design/icons.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import 'press.dart';
import '../widgets/chhers_loader.dart';

/// quiet:无底 text2 字,用于取消、回复这类次要文字操作(规格 §6.3)
enum AppButtonVariant {
  primary,
  tinted,
  plain,
  quiet,
  destructive,
  composerSend,
}

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

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final reduced = MediaQuery.disableAnimationsOf(context);
    final enabled = onPressed != null || state != AppButtonState.idle;
    final composerSend = variant == AppButtonVariant.composerSend;
    final height = composerSend
        ? ComposerTokens.sendHeight
        : small
        ? AppSizes.compactButtonHeight
        : AppSizes.buttonHeight;

    // 颜色:禁用一律 fill 底 + text3 字;其余按变体取令牌。
    // 主按钮不用纯色:漆面渐变 + 红调投影,是每屏唯一的实心红。
    final primary = variant == AppButtonVariant.primary;
    final filled =
        primary || composerSend || variant == AppButtonVariant.tinted;
    final Color? base = !filled
        ? null
        : !enabled
        ? t.fill
        : primary
        ? null // 渐变走 decoration,不走 color
        : t.accentFill;
    final foreground = !enabled
        ? t.text3
        : switch (variant) {
            AppButtonVariant.primary ||
            AppButtonVariant.composerSend => t.onAccent,
            AppButtonVariant.tinted || AppButtonVariant.plain => t.accent,
            AppButtonVariant.quiet => t.text2,
            AppButtonVariant.destructive =>
              Theme.of(context).brightness == Brightness.dark
                  ? Radix.red11Dark
                  : Radix.red11Light,
          };
    final textStyle =
        (composerSend
                ? ComposerTokens.sendLabel
                : small ||
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
        Positioned.fill(
          child: Center(
            child: ChhersSpinner(
              active: state == AppButtonState.busy,
              color: foreground,
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
                    color: filled ? t.onAccent : t.green,
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
        child: composerSend
            ? _composerSendContent(context, content, textStyle)
            : Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: !filled
                      ? AppSpace.textButtonInset
                      : (small ? 16 : 24),
                ),
                child: Center(widthFactor: 1, child: content),
              ),
      ),
      builder: (_, v, child) {
        final progress = v.clamp(0.0, 1.0);
        final BoxDecoration decoration;
        if (composerSend) {
          final gradient = enabled ? t.composerSendGradient : null;
          final showGradient = gradient != null && progress <= 0.001;
          final startColor = !enabled
              ? t.fill
              : gradient == null
              ? t.accent
              : t.btnTop;
          decoration = BoxDecoration(
            gradient: showGradient ? gradient : null,
            color: showGradient
                ? null
                : Color.lerp(startColor, t.green, progress),
            borderRadius: BorderRadius.circular(ComposerTokens.sendRadius),
          );
        } else if (primary && enabled) {
          // 成功态渐变过渡到绿色:从渐变顶端色向绿插值,底色不跳变
          decoration = BoxDecoration(
            gradient: progress <= 0.001 ? t.btnGradient : null,
            color: progress <= 0.001
                ? null
                : Color.lerp(t.btnTop, t.green, progress),
            boxShadow: progress <= 0.001 ? t.btnShadow : null,
            borderRadius: BorderRadius.circular(AppRadii.full),
          );
        } else {
          decoration = BoxDecoration(
            color: base == null ? null : Color.lerp(base, t.green, progress),
            borderRadius: BorderRadius.circular(AppRadii.full),
          );
        }
        return DecoratedBox(
          key: surfaceKey,
          decoration: decoration,
          child: child,
        );
      },
    );

    return PressScale(
      onTap: state == AppButtonState.idle ? onPressed : null,
      semanticLabel: label,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        child: Center(widthFactor: 1, heightFactor: 1, child: surface),
      ),
    );
  }

  Widget _composerSendContent(
    BuildContext context,
    Widget content,
    TextStyle style,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: DefaultTextStyle.of(context).style.merge(style),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
      maxLines: 1,
    )..layout();
    final labelWidth = painter.width;
    painter.dispose();
    return LayoutBuilder(
      builder: (_, constraints) {
        final width = constraints.constrainWidth(
          labelWidth + 2 * ComposerTokens.sendInset,
        );
        final inset = ((width - labelWidth) / 2).clamp(
          0.0,
          ComposerTokens.sendInset,
        );
        return SizedBox(
          width: width,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: inset),
            child: Center(child: content),
          ),
        );
      },
    );
  }
}
