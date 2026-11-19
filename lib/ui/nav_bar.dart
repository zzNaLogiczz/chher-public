/// 顶栏:浮动圆钮 + 滚动渐隐 + 居中小标题(规格 §6.1)
///
/// 顶栏没有底色。内容滚动后,顶部铺一层"页面底色 → 透明"的渐变,
/// 让滚上来的内容自然淡出,而不是被一条直线切断。
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

import '../design/motion.dart';
import '../design/thread_page_tokens.dart';
import '../design/tokens.dart';
import '../design/typography.dart';

class NavOverlay extends StatefulWidget {
  static const edgeKey = ValueKey('nav-edge-fade');
  static const inlineTitleKey = ValueKey('nav-inline-title');

  /// 状态栏下方按钮行的高度
  static const double barHeight = 52;

  /// 按钮行下方继续淡出的距离
  static const double fadeBand = 24;

  /// 遮罩从全透明到不透明所需的滚动距离
  static const double fadeDistance = 12;

  final Widget? leading;
  final List<Widget> actions;
  final String inlineTitle;
  final ValueListenable<double> scrollOffset;

  /// 滚动超过这个距离(大标题离开)后显示居中小标题
  final double collapseAt;
  final ValueListenable<bool>? titleVisible;
  final ValueListenable<double>? readingProgress;
  final ValueListenable<bool>? readingProgressVisible;
  final Color background;

  /// 小标题左右的最小留白;控件更宽时按实际宽度避让。
  final double titleInset;

  /// 正文已固定在顶栏下方时,不再把渐隐遮罩画到工具栏上。
  final bool fadeBelowBar;

  /// 漆面顶栏:小标题与遮罩在奶白(漆面)和纸面色之间随滚动切换
  final bool onLac;

  const NavOverlay({
    super.key,
    this.leading,
    this.actions = const [],
    required this.inlineTitle,
    required this.scrollOffset,
    required this.collapseAt,
    this.titleVisible,
    this.readingProgress,
    this.readingProgressVisible,
    required this.background,
    this.titleInset = 72,
    this.fadeBelowBar = true,
    this.onLac = false,
  });

  @override
  State<NavOverlay> createState() => _NavOverlayState();
}

class _NavOverlayState extends State<NavOverlay>
    with SingleTickerProviderStateMixin {
  late final _title = SingleMotionController(
    motion: AppMotion.reveal,
    vsync: this,
    initialValue: 0,
  );
  double _target = 0;

  @override
  void initState() {
    super.initState();
    widget.scrollOffset.addListener(_sync);
    widget.titleVisible?.addListener(_sync);
  }

  @override
  void didUpdateWidget(covariant NavOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollOffset != widget.scrollOffset) {
      oldWidget.scrollOffset.removeListener(_sync);
      widget.scrollOffset.addListener(_sync);
    }
    if (oldWidget.titleVisible != widget.titleVisible) {
      oldWidget.titleVisible?.removeListener(_sync);
      widget.titleVisible?.addListener(_sync);
    }
    _sync();
  }

  // 小标题按阈值切换,用弹簧显隐,不随滚动比例渐变
  void _sync() {
    final next =
        (widget.titleVisible?.value ??
            (widget.scrollOffset.value >= widget.collapseAt))
        ? 1.0
        : 0.0;
    if (next == _target) return;
    _target = next;
    if (MediaQuery.disableAnimationsOf(context)) {
      _title.value = next;
    } else {
      _title.animateTo(next);
    }
  }

  @override
  void dispose() {
    widget.scrollOffset.removeListener(_sync);
    widget.titleVisible?.removeListener(_sync);
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final solid = top + NavOverlay.barHeight;
    final height = solid + (widget.fadeBelowBar ? NavOverlay.fadeBand : 0);
    const edgeInset = 10.0;
    const middleSpacing = 8.0;
    final sideConstraints = BoxConstraints(
      minWidth: math.max(0, widget.titleInset - edgeInset - middleSpacing),
    );
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              // 遮罩色随 _title(漆面→纸面)过渡、透明度随滚动距离。
              // 颜色必须在动画 builder 内现算:build 局部变量会被闭包
              // 捕获成首帧值,弹簧走到 1 也不会重算。
              child: AnimatedBuilder(
                animation: _title,
                builder: (context, _) {
                  final v = _title.value.clamp(0.0, 1.0);
                  final tt = AppTokens.of(context);
                  final topColor = widget.onLac
                      ? Color.lerp(tt.lacTop, widget.background, v)!
                      : widget.background;
                  return ValueListenableBuilder<double>(
                    valueListenable: widget.scrollOffset,
                    builder: (_, offset, child) => Opacity(
                      key: NavOverlay.edgeKey,
                      opacity: (offset / NavOverlay.fadeDistance).clamp(
                        0.0,
                        1.0,
                      ),
                      child: child,
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            topColor,
                            topColor,
                            topColor.withValues(alpha: 0),
                          ],
                          stops: [0, solid / height, 1],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          if ((widget.readingProgress, widget.readingProgressVisible) case (
            final progress?,
            final visibility?,
          ))
            Positioned(
              top: solid - ThreadPageTokens.progressHeight,
              left: 0,
              right: 0,
              child: ValueListenableBuilder<bool>(
                valueListenable: visibility,
                builder: (context, visible, _) => visible
                    ? IgnorePointer(
                        child: ValueListenableBuilder<double>(
                          valueListenable: progress,
                          builder: (context, value, _) => value <= 0
                              ? const SizedBox.shrink()
                              : Transform.scale(
                                  key: const ValueKey(
                                    'thread-reading-progress',
                                  ),
                                  alignment: Alignment.centerLeft,
                                  scaleX: value.clamp(0.0, 1.0),
                                  child: ColoredBox(
                                    color: AppTokens.of(context).accent,
                                    child: const SizedBox(
                                      height: ThreadPageTokens.progressHeight,
                                    ),
                                  ),
                                ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          Positioned(
            top: top,
            left: 0,
            right: 0,
            height: NavOverlay.barHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: edgeInset),
              child: NavigationToolbar(
                centerMiddle: true,
                middleSpacing: middleSpacing,
                leading: ConstrainedBox(
                  constraints: sideConstraints,
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: 1,
                    child: widget.leading,
                  ),
                ),
                middle: IgnorePointer(
                  // 小标题颜色随 _title 过渡(漆面奶白→纸面正文),builder 内现算
                  child: AnimatedBuilder(
                    animation: _title,
                    builder: (context, _) {
                      final v = _title.value.clamp(0.0, 1.0);
                      final tt = AppTokens.of(context);
                      return Opacity(
                        key: NavOverlay.inlineTitleKey,
                        opacity: v,
                        child: Text(
                          widget.inlineTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.headline.copyWith(
                            color: widget.onLac
                                ? Color.lerp(tt.onLac, tt.text, v)!
                                : tt.text,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                trailing: ConstrainedBox(
                  constraints: sideConstraints,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      for (var i = 0; i < widget.actions.length; i++) ...[
                        if (i > 0) const SizedBox(width: 6),
                        widget.actions[i],
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared expanded header for the four primary destinations.
class TabHeader extends StatelessWidget {
  const TabHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.actionCount = 0,
  });

  final String title;
  final String? eyebrow;
  final int actionCount;

  static double _eyebrowHeight(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(AppType.sizeFootnote) *
      (TabChromeTokens.eyebrowHeight / AppType.sizeFootnote);

  static double _titleHeight(BuildContext context) => math.max(
    TabChromeTokens.actionSize,
    MediaQuery.textScalerOf(context).scale(AppType.sizeLargeTitle) *
        (AppSpace.titleRow / AppType.sizeLargeTitle),
  );

  static double actionTop(BuildContext context) =>
      TabChromeTokens.titleTop +
      _eyebrowHeight(context) +
      TabChromeTokens.eyebrowGap +
      (_titleHeight(context) - TabChromeTokens.actionSize) / 2;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final onLac = t.style == AppearanceStyle.cinnabar;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        TabChromeTokens.pageInset,
        TabChromeTokens.titleTop,
        TabChromeTokens.pageInset,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: _eyebrowHeight(context),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: eyebrow == null
                  ? null
                  : Text(
                      eyebrow!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.footnote.copyWith(
                        color: onLac ? t.onLac2 : t.text2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: TabChromeTokens.eyebrowGap),
          Padding(
            padding: EdgeInsetsDirectional.only(
              end: actionCount * TabChromeTokens.actionSize,
            ),
            child: SizedBox(
              height: _titleHeight(context),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Semantics(
                  header: true,
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.largeTitle.copyWith(
                      color: onLac ? t.onLac : t.text,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 大标题行:可选眉题(日期等)+ 大标题 + 同一行右侧的一个圆钮
class LargeTitleHeader extends StatelessWidget {
  final String title;
  final String? eyebrow;
  final Widget? accessory;

  /// 压在漆面顶栏上:眉题淡朱、标题奶白
  final bool onLac;

  const LargeTitleHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.accessory,
    this.onLac = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpace.screen,
        0,
        accessory == null ? AppSpace.screen : 10,
        4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            eyebrow ?? '',
            style: AppType.footnote.copyWith(
              color: onLac ? t.onLac2 : t.text3,
              fontWeight: FontWeight.w600,
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppSpace.titleRow),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.largeTitle.copyWith(
                      color: onLac ? t.onLac : t.text,
                    ),
                  ),
                ),
                ?accessory,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
