/// 统一状态视图:加载 / 空 / 错误 / 登录墙 / 无权限
///
/// 文案只说状态与下一步,不解释原因(docs/DESIGN.md §7)。
library;

import 'package:flutter/material.dart';
import '../design/list_end_tokens.dart';
import '../design/motion.dart';

import '../design/tokens.dart';
import '../design/typography.dart';
import '../ui/app_button.dart';
import '../models/models.dart';
import '../network/chh_fetcher.dart';
import 'chhers_loader.dart';
import 'chhers_loading_transition.dart';
import 'expressive_controls.dart';

/// Space below the text in a fixed-height, vertically centered final control.
double centeredLabelBottomInset(
  BuildContext context,
  String label,
  TextStyle style,
  double height,
) {
  final defaults = DefaultTextStyle.of(context);
  final resolved = defaults.style.merge(style);
  final painter = TextPainter(
    text: TextSpan(
      text: label,
      style: MediaQuery.boldTextOf(context)
          ? resolved.merge(const TextStyle(fontWeight: FontWeight.bold))
          : resolved,
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    textHeightBehavior:
        defaults.textHeightBehavior ??
        DefaultTextHeightBehavior.maybeOf(context),
    locale: Localizations.maybeLocaleOf(context),
    maxLines: 1,
  )..layout();
  final inset = (height - painter.height) / 2;
  painter.dispose();
  return inset < 0 ? 0 : inset;
}

class StateView extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const StateView({
    super.key,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  /// 加载中只给指示器,不配文字
  static Widget loading() => const Center(child: ChhersLoader());

  static Widget empty({String message = '这里还没有内容'}) =>
      StateView(icon: AppIcons.inbox, message: message);

  /// 站点消息页按语义分流为不同状态(PAGE_SPEC §二.3)
  static Widget forMessage(
    PageMessage m, {
    VoidCallback? onLogin,
    VoidCallback? onPassword,
  }) {
    return switch (m.kind) {
      PageMessageKind.loginRequired => StateView(
        icon: AppIcons.lock,
        message: '需登录',
        actionLabel: '登录',
        onAction: onLogin,
      ),
      PageMessageKind.forumPassword => StateView(
        icon: AppIcons.lock,
        message: '本版块需要密码',
        actionLabel: '输入密码',
        onAction: onPassword,
      ),
      PageMessageKind.permissionDenied => const StateView(
        icon: AppIcons.forbidden,
        message: '没有访问权限',
      ),
      PageMessageKind.featureUnavailable => const StateView(
        icon: AppIcons.forbidden,
        message: '该功能未开放',
      ),
      PageMessageKind.message => StateView(
        icon: AppIcons.info,
        message: m.text,
      ),
    };
  }

  static Widget error(Object e, {VoidCallback? onRetry}) {
    final networkFailure = e is ChhAllBlockedError;
    final blocked = networkFailure && !e.isConnectionFailure;
    return StateView(
      icon: blocked ? AppIcons.verified : AppIcons.warning,
      message: networkFailure
          ? (blocked ? '网络被拦截，请稍后重试' : '无法连接论坛，请稍后重试')
          : '加载失败',
      actionLabel: onRetry == null ? null : '重试',
      onAction: onRetry,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return ExpressivePageReveal(
      active: true,
      animateOnMount: true,
      revision: (icon, message, actionLabel),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 线条图标 + 标题式文字 + 次要按钮:只说状态和下一步
              Icon(icon, size: 52, color: t.text3),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppType.headline.copyWith(color: t.text),
              ),
              if (actionLabel != null) ...[
                const SizedBox(height: 16),
                AppButton(
                  label: actionLabel!,
                  onPressed: onAction,
                  variant: AppButtonVariant.tinted,
                  small: true,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 列表尾部加载条:翻页时用,不抢视觉
class ListFooter extends StatelessWidget {
  final bool loading;
  final bool exhausted;
  final String endLabel;
  final double precedingBottomPadding;
  final double followingBottomPadding;

  const ListFooter({
    super.key,
    required this.loading,
    this.exhausted = false,
    this.endLabel = '没有更多了',
    this.precedingBottomPadding = 0,
    this.followingBottomPadding = 0,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final reduced = MediaQuery.disableAnimationsOf(context);
    final style = AppType.footnote.copyWith(color: t.text3);
    Widget marker(Widget child) => Padding(
      padding: EdgeInsets.only(
        top: ListEndTokens.markerPadding(precedingBottomPadding),
        bottom: ListEndTokens.markerPadding(followingBottomPadding),
      ),
      child: Center(child: child),
    );
    final content = ChhersLoadingTransition(
      size: ChhersLoaderSize.list,
      placeholderBuilder: marker,
      child: loading
          ? null
          : exhausted
          ? marker(Text(endLabel, style: style))
          : const SizedBox.shrink(),
    );
    if (reduced) return content;
    return AnimatedSize(
      duration: AppMotion.revealDuration,
      curve: AppMotion.revealCurve,
      alignment: Alignment.topCenter,
      child: content,
    );
  }
}
