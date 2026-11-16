/// 弹层骨架与打开方式(规格 §6.10)
///
/// 全 app 的弹层只有这一种外观:拖动条、标题行(可带计数)+ 关闭圆钮、
/// 可选的一行上下文。开合与松手回弹都用 [AppMotion.sheet] 弹簧。
library;

import 'package:flutter/material.dart';
import 'package:smooth_sheets/smooth_sheets.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/shapes.dart';
import '../design/sheet_tokens.dart';
import 'sheet_route.dart';
export 'sheet_route.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import 'press.dart';

class SheetScaffold extends StatelessWidget {
  final String title;
  final int? count;

  /// 文章名、被回复的楼等上下文,只占一行
  final String? contextLine;
  final Widget body;
  final Widget? footer;

  /// 默认关闭当前路由
  final VoidCallback? onClose;

  const SheetScaffold({
    super.key,
    required this.title,
    this.count,
    this.contextLine,
    required this.body,
    this.footer,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SheetHeader(
        title: title,
        count: count,
        contextLine: contextLine,
        onClose: onClose,
      ),
      Flexible(child: body),
      ?footer,
    ],
  );
}

/// 弹层头部:拖动条 + 标题(可带计数)+ 关闭圆钮 + 可选的一行上下文。
/// 自带布局的弹层(评论、楼内回复)直接用它当顶栏。
class SheetHeader extends StatelessWidget {
  final String title;
  final int? count;
  final String? contextLine;
  final VoidCallback? onClose;
  final String closeTooltip;
  final Key? grabberKey;
  final Widget? trailing;
  final double trailingMinWidth;

  const SheetHeader({
    super.key,
    required this.title,
    this.count,
    this.contextLine,
    this.onClose,
    this.closeTooltip = '关闭',
    this.grabberKey,
    this.trailing,
    this.trailingMinWidth = 0,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: '拖动展开或收起',
          child: SizedBox(
            key: grabberKey,
            height: 21,
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: t.fill2,
                  borderRadius: BorderRadius.circular(AppRadii.bar),
                ),
                child: const SizedBox(width: 36, height: 5),
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpace.screen,
            0,
            8,
            contextLine == null ? 8 : 0,
          ),
          child: Row(
            children: [
              Expanded(
                child: HeaderTrailingRow(
                  trailing: trailing,
                  trailingMinWidth: trailingMinWidth,
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.headline.copyWith(color: t.text),
                        ),
                      ),
                      if (count != null) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '$count',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.headline.copyWith(color: t.text3),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              _CloseButton(
                tooltip: closeTooltip,
                onTap: onClose ?? () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
        if (contextLine != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.screen,
              0,
              AppSpace.screen,
              12,
            ),
            child: Text(
              contextLine!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.footnote.copyWith(color: t.text3),
            ),
          ),
      ],
    );
  }
}

/// Gives a compact trailing control the width remaining after its heading.
class HeaderTrailingRow extends StatelessWidget {
  final Widget leading;
  final Widget? trailing;
  final double trailingMinWidth;

  const HeaderTrailingRow({
    super.key,
    required this.leading,
    this.trailing,
    this.trailingMinWidth = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (trailing == null) return leading;
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth:
                  (constraints.maxWidth -
                          trailingMinWidth -
                          CommentModeTokens.headingGap)
                      .clamp(0, double.infinity),
            ),
            child: leading,
          ),
          const SizedBox(width: CommentModeTokens.headingGap),
          Expanded(child: trailing!),
        ],
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  final VoidCallback onTap;
  final String tooltip;
  const _CloseButton({required this.onTap, required this.tooltip});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Tooltip(
      message: tooltip,
      child: PressScale(
        onTap: onTap,
        semanticLabel: tooltip,
        child: SizedBox.square(
          dimension: 44,
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(color: t.fill, shape: BoxShape.circle),
              child: SizedBox.square(
                dimension: 30,
                child: Icon(AppIcons.dismiss, size: 18, color: t.text2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 打开一个弹层。`expandable` 为 true 时有半屏 / 全屏两档,否则按内容高度。
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool expandable = false,
}) {
  final t = AppTokens.of(context);
  final reduced = MediaQuery.disableAnimationsOf(context);
  return Navigator.of(context).push<T>(
    AppSheetRoute<T>(
      builder: (context) => Sheet(
        initialOffset: SheetOffset(expandable ? .62 : 1),
        snapGrid: expandable
            ? const SheetSnapGrid(snaps: [SheetOffset(.62), SheetOffset(1)])
            : const SheetSnapGrid.single(snap: SheetOffset(1)),
        physics: AppSheetPhysics.of(context),
        decoration: SheetDecorationBuilder(
          size: expandable ? SheetSize.stretch : SheetSize.fit,
          builder: (context, child) => AppSheetSurface(child: child),
        ),
        child: SafeArea(top: false, child: builder(context)),
      ),
      barrierColor: t.scrim,
      reduced: reduced,
    ),
  );
}

/// 弹层面:四角 40 连续曲率圆角、surface 底;自带 Sheet 的弹层也用它
///
/// 不画 e3 阴影:弹层下面总有遮罩,阴影看不出来,而对整张弹层做模糊
/// 在真机上每帧要 Raster 约 8ms(QA12)。透明 Material 给文字默认样式。
class AppSheetSurface extends StatelessWidget {
  final Widget child;
  const AppSheetSurface({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    const radius = BorderRadius.all(Radius.circular(AppSheetTokens.radius));
    final shape = kContinuousCorners
        ? const RoundedSuperellipseBorder(borderRadius: radius)
        : const RoundedRectangleBorder(borderRadius: radius);
    final content = Material(type: MaterialType.transparency, child: child);
    return DecoratedBox(
      decoration: ShapeDecoration(color: t.surface, shape: shape),
      child: kContinuousCorners
          ? ClipRSuperellipse(borderRadius: radius, child: content)
          : ClipRRect(borderRadius: radius, child: content),
    );
  }
}
