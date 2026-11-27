/// 浮在内容上的顶栏控件:圆钮、胶囊组、计数角标(规格 §6.2)
library;

import 'package:flutter/material.dart';

import '../design/motion.dart';
import '../design/forum_tokens.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import 'press.dart';

const double _visual = 38;
const double _hit = 44;
const double _iconSize = 20;

/// 白色"玻璃"正圆按钮，默认视觉直径 38，命中区 44。
class ChromeButton extends StatelessWidget {
  static const surfaceKey = ValueKey('chrome-button-surface');

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// 压在图片上时用深色玻璃 + 白色图标
  final bool onImage;

  /// 开关类按钮的开启态,图标改用强调色
  final bool selected;
  final int badgeCount;
  final double visualSize;

  /// 压在漆面顶栏上时用奶白玻璃 + 奶白图标,不投影
  final bool onLac;

  const ChromeButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.onImage = false,
    this.selected = false,
    this.badgeCount = 0,
    this.onLac = false,
    this.visualSize = _visual,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final color = onImage
        ? Colors.white
        : onPressed == null
        ? t.text3
        : selected
        ? t.accent
        : t.text;
    return Tooltip(
      message: tooltip,
      child: PressScale(
        onTap: onPressed,
        semanticLabel: tooltip,
        child: SizedBox.square(
          dimension: _hit,
          child: Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                DecoratedBox(
                  key: surfaceKey,
                  decoration: BoxDecoration(
                    color: onImage
                        ? t.glassOnImage
                        : onLac
                        ? const Color.fromRGBO(255, 248, 245, .16)
                        : t.glass,
                    shape: BoxShape.circle,
                    boxShadow: onImage || onLac ? null : t.shadowE1,
                  ),
                  child: SizedBox.square(
                    dimension: visualSize,
                    child: Icon(
                      icon,
                      size: _iconSize,
                      color: onLac ? t.onLac : color,
                    ),
                  ),
                ),
                Positioned(
                  top: -4,
                  right: -6,
                  child: CountBadge(count: badgeCount),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ChromeGroupItem {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// 开关类操作的开启态,图标改用强调色
  final bool selected;
  final bool dot;
  const ChromeGroupItem({
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.selected = false,
    this.dot = false,
  });
}

/// 同一侧多个操作合进一个 38 高胶囊,每格命中区 44,按下格内铺 `fill`。
class ChromeGroup extends StatelessWidget {
  static const surfaceKey = ValueKey('chrome-group-surface');
  static const double _inset = 4;

  final List<ChromeGroupItem> items;
  final bool onImage;

  /// 压在漆面顶栏上:奶白玻璃、无投影、图标奶白
  final bool onLac;

  const ChromeGroup({
    super.key,
    required this.items,
    this.onImage = false,
    this.onLac = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final radius = BorderRadius.circular(AppRadii.full);
    return SizedBox(
      height: _hit,
      child: Stack(
        children: [
          Positioned(
            top: (_hit - _visual) / 2,
            bottom: (_hit - _visual) / 2,
            left: 0,
            right: 0,
            child: DecoratedBox(
              key: surfaceKey,
              decoration: BoxDecoration(
                color: onImage
                    ? t.glassOnImage
                    : onLac
                    ? const Color.fromRGBO(255, 248, 245, .16)
                    : t.glass,
                borderRadius: radius,
                boxShadow: onImage || onLac ? null : t.shadowE1,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _inset),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final item in items)
                  Tooltip(
                    message: item.tooltip,
                    child: PressHighlight(
                      onTap: item.onPressed,
                      semanticLabel: item.tooltip,
                      color: t.fill,
                      paintInset: const EdgeInsets.symmetric(
                        vertical: (_hit - _visual) / 2,
                      ),
                      borderRadius: radius,
                      child: SizedBox.square(
                        dimension: _hit,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Icon(
                              item.icon,
                              size: _iconSize,
                              color: onLac
                                  ? t.onLac
                                  : onImage
                                  ? Colors.white
                                  : item.onPressed == null
                                  ? t.text3
                                  : item.selected
                                  ? t.accent
                                  : t.text,
                            ),
                            Positioned(
                              top: 7,
                              right: 7,
                              child: BadgeAppearance(
                                visible: item.dot,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: t.accent,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const SizedBox.square(
                                    dimension: ForumTokens.activityDot,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
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

enum BadgeTone { alert, neutral }

/// 不带数字的提示红点,出现用 pop,清零用 tap 缩小淡出。
class DotBadge extends StatelessWidget {
  static const surfaceKey = ValueKey('dot-badge-surface');
  static const double size = 8;
  final bool visible;
  final Color? ringColor;
  final Color? color;
  const DotBadge({
    super.key,
    required this.visible,
    this.ringColor,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final dot = DecoratedBox(
      key: surfaceKey,
      decoration: ShapeDecoration(
        color: color ?? AppTokens.of(context).red,
        shape: CircleBorder(
          side: ringColor == null
              ? BorderSide.none
              : BorderSide(
                  color: ringColor!,
                  width: 1.5,
                  strokeAlign: BorderSide.strokeAlignOutside,
                ),
        ),
      ),
      child: const SizedBox.square(dimension: size),
    );
    if (color != null && MediaQuery.disableAnimationsOf(context)) {
      return AnimatedSwitcher(
        duration: AppMotion.reducedFade,
        child: visible ? dot : const SizedBox.shrink(),
      );
    }
    return BadgeAppearance(visible: visible, child: dot);
  }
}

/// Shared appearance for counters and source-backed unread indicators.
class BadgeAppearance extends StatefulWidget {
  final bool visible;
  final Widget child;
  const BadgeAppearance({
    super.key,
    required this.visible,
    required this.child,
  });

  @override
  State<BadgeAppearance> createState() => _BadgeAppearanceState();
}

class _BadgeAppearanceState extends State<BadgeAppearance>
    with SingleTickerProviderStateMixin {
  late final _scale = AnimationController.unbounded(
    vsync: this,
    value: widget.visible ? .6 : 0,
  );
  bool _started = false;

  void _change() {
    if (widget.visible && _scale.value == 0) _scale.value = .6;
    final target = widget.visible ? 1.0 : 0.0;
    if (_scale.value == target && !_scale.isAnimating) return;
    AppMotion.settle(
      _scale,
      target: target,
      motion: widget.visible ? AppMotion.pop : AppMotion.tap,
      reduced: MediaQuery.disableAnimationsOf(context),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started || MediaQuery.disableAnimationsOf(context)) {
      _started = true;
      _change();
    }
  }

  @override
  void didUpdateWidget(covariant BadgeAppearance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible) _change();
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _scale,
    child: widget.child,
    builder: (context, child) {
      final scale = _scale.value.clamp(0.0, 2.0);
      if (scale == 0) return const SizedBox.shrink();
      return Opacity(
        opacity: widget.visible ? 1 : scale.clamp(0.0, 1.0),
        child: Transform.scale(scale: scale, child: child),
      );
    },
  );
}

/// 数字变化上下滚动一格,保持真实计数,不显示过渡中的虚构数字。
class CountBadge extends StatefulWidget {
  static const surfaceKey = ValueKey('count-badge-surface');
  final int count;
  final BadgeTone tone;
  final Color? color;
  final Color? textColor;
  const CountBadge({
    super.key,
    required this.count,
    this.tone = BadgeTone.alert,
    this.color,
    this.textColor,
  });

  @override
  State<CountBadge> createState() => _CountBadgeState();
}

class _CountBadgeState extends State<CountBadge>
    with SingleTickerProviderStateMixin {
  late final _roll = AnimationController.unbounded(vsync: this, value: 1);
  late int _shown = widget.count;
  int? _previous;

  @override
  void didUpdateWidget(covariant CountBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.count == oldWidget.count || widget.count <= 0) return;
    _previous = oldWidget.count > 0 ? _shown : null;
    _shown = widget.count;
    final velocity = _roll.velocity;
    _roll.value = _previous == null ? 1 : 0;
    AppMotion.settle(
      _roll,
      target: 1,
      motion: AppMotion.select,
      velocity: velocity,
      reduced: MediaQuery.disableAnimationsOf(context),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _roll.value = 1;
  }

  @override
  void dispose() {
    _roll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final alert = widget.tone == BadgeTone.alert;
    const lineHeightEm = 1.2;
    final style = AppType.caption.copyWith(
      fontWeight: FontWeight.w700,
      height: lineHeightEm,
      leadingDistribution: TextLeadingDistribution.even,
      color: widget.textColor ?? (alert ? t.onAccent : t.bg),
    );
    final fontSize = MediaQuery.textScalerOf(
      context,
    ).scale(AppType.sizeCaption);
    final lineHeight = fontSize * lineHeightEm;
    Widget number(int value) {
      final label = '$value';
      // The glyph for 1 leaves more blank space at its trailing edge.
      final inset =
          (label.endsWith('1') ? .075 : 0) - (label.startsWith('1') ? .02 : 0);
      return Center(
        widthFactor: 1,
        heightFactor: 1,
        child: SizedBox(
          height: lineHeight,
          child: Baseline(
            // Align the numeral ink center with the center of its rolling slot.
            baseline: lineHeight / 2 + fontSize * .36,
            baselineType: TextBaseline.alphabetic,
            child: Transform.translate(
              offset: Offset(inset * fontSize, 0),
              child: Text(label, style: style, maxLines: 1, softWrap: false),
            ),
          ),
        ),
      );
    }

    return BadgeAppearance(
      visible: widget.count > 0,
      child: DecoratedBox(
        key: CountBadge.surfaceKey,
        decoration: BoxDecoration(
          color: widget.color ?? (alert ? t.red : t.text),
          borderRadius: BorderRadius.circular(AppRadii.full),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ClipRect(
              child: AnimatedBuilder(
                animation: _roll,
                builder: (context, _) {
                  final previous = _previous;
                  if (previous == null || _roll.value == 1) {
                    return number(_shown);
                  }
                  final direction = _shown >= previous ? 1.0 : -1.0;
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      ExcludeSemantics(
                        child: FractionalTranslation(
                          translation: Offset(0, -direction * _roll.value),
                          child: number(previous),
                        ),
                      ),
                      FractionalTranslation(
                        translation: Offset(0, direction * (1 - _roll.value)),
                        child: number(_shown),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
