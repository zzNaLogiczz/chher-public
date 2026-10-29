/// 顶栏:浮动圆钮 + 滚动渐隐 + 居中小标题(规格 §6.1)
///
/// 顶栏没有底色。内容滚动后,顶部铺一层"页面底色 → 透明"的渐变,
/// 让滚上来的内容自然淡出,而不是被一条直线切断。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

import '../design/motion.dart';
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
  final Color background;

  /// 居中小标题左右让出的宽度;右侧放了较宽的操作时调大,避免标题压到按钮下
  final double titleInset;

  const NavOverlay({
    super.key,
    this.leading,
    this.actions = const [],
    required this.inlineTitle,
    required this.scrollOffset,
    required this.collapseAt,
    required this.background,
    this.titleInset = 72,
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
  }

  @override
  void didUpdateWidget(covariant NavOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollOffset != widget.scrollOffset) {
      oldWidget.scrollOffset.removeListener(_sync);
      widget.scrollOffset.addListener(_sync);
    }
    _sync();
  }

  // 小标题按阈值切换,用弹簧显隐,不随滚动比例渐变
  void _sync() {
    final next = widget.scrollOffset.value >= widget.collapseAt ? 1.0 : 0.0;
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
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final top = MediaQuery.paddingOf(context).top;
    final solid = top + NavOverlay.barHeight;
    final height = solid + NavOverlay.fadeBand;
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: ValueListenableBuilder<double>(
                valueListenable: widget.scrollOffset,
                builder: (_, offset, child) => Opacity(
                  key: NavOverlay.edgeKey,
                  opacity: (offset / NavOverlay.fadeDistance).clamp(0.0, 1.0),
                  child: child,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        widget.background,
                        widget.background,
                        widget.background.withValues(alpha: 0),
                      ],
                      stops: [0, solid / height, 1],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: top,
            left: 0,
            right: 0,
            height: NavOverlay.barHeight,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: widget.titleInset),
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _title,
                      builder: (_, child) => Opacity(
                        key: NavOverlay.inlineTitleKey,
                        opacity: _title.value.clamp(0.0, 1.0),
                        child: child,
                      ),
                      child: Text(
                        widget.inlineTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.headline.copyWith(color: t.text),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      ?widget.leading,
                      const Spacer(),
                      for (var i = 0; i < widget.actions.length; i++) ...[
                        if (i > 0) const SizedBox(width: 6),
                        widget.actions[i],
                      ],
                    ],
                  ),
                ),
              ],
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

  const LargeTitleHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.accessory,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpace.screen,
        2,
        accessory == null ? AppSpace.screen : 10,
        10,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (eyebrow != null)
            Text(
              eyebrow!,
              style: AppType.footnote.copyWith(
                color: t.text3,
                fontWeight: FontWeight.w600,
              ),
            ),
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.largeTitle.copyWith(color: t.text),
                ),
              ),
              ?accessory,
            ],
          ),
        ],
      ),
    );
  }
}
