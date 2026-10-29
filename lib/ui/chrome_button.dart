/// 浮在内容上的顶栏控件:圆钮、胶囊组、计数角标(规格 §6.2)
library;

import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

import '../design/motion.dart';
import '../design/tokens.dart';
import 'press.dart';

const double _visual = 38;
const double _hit = 44;
const double _iconSize = 20;

/// 白色"玻璃"正圆按钮:视觉直径 38,命中区 44。
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

  const ChromeButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.onImage = false,
    this.selected = false,
    this.badgeCount = 0,
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
                    color: onImage ? t.glassOnImage : t.glass,
                    shape: BoxShape.circle,
                    boxShadow: onImage ? null : t.shadowE1,
                  ),
                  child: SizedBox.square(
                    dimension: _visual,
                    child: Icon(icon, size: _iconSize, color: color),
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
  const ChromeGroupItem({
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.selected = false,
  });
}

/// 同一侧多个操作合进一个 38 高胶囊,每格命中区 44,按下格内铺 `fill`。
class ChromeGroup extends StatelessWidget {
  static const surfaceKey = ValueKey('chrome-group-surface');
  static const double _inset = 4;

  final List<ChromeGroupItem> items;
  final bool onImage;

  const ChromeGroup({super.key, required this.items, this.onImage = false});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final radius = BorderRadius.circular(_visual / 2);
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
                color: onImage ? t.glassOnImage : t.glass,
                borderRadius: radius,
                boxShadow: onImage ? null : t.shadowE1,
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
                      borderRadius: radius,
                      child: SizedBox.square(
                        dimension: _hit,
                        child: Icon(
                          item.icon,
                          size: _iconSize,
                          color: onImage
                              ? Colors.white
                              : item.onPressed == null
                              ? t.text3
                              : item.selected
                              ? t.accent
                              : t.text,
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

/// 不带数字的提示红点:直径 8,出现与消失用 [AppMotion.pop]
class DotBadge extends StatefulWidget {
  static const surfaceKey = ValueKey('dot-badge-surface');
  static const double size = 8;

  final bool visible;

  const DotBadge({super.key, required this.visible});

  @override
  State<DotBadge> createState() => _DotBadgeState();
}

class _DotBadgeState extends State<DotBadge>
    with SingleTickerProviderStateMixin {
  late final _scale = SingleMotionController(
    motion: AppMotion.pop,
    vsync: this,
    initialValue: widget.visible ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant DotBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible == oldWidget.visible) return;
    final target = widget.visible ? 1.0 : 0.0;
    if (MediaQuery.disableAnimationsOf(context)) {
      _scale.value = target;
    } else {
      _scale.animateTo(target);
    }
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return AnimatedBuilder(
      animation: _scale,
      builder: (context, _) {
        final scale = _scale.value.clamp(0.0, 2.0);
        if (scale == 0) return const SizedBox.square(dimension: DotBadge.size);
        return Transform.scale(
          scale: scale,
          child: DecoratedBox(
            key: DotBadge.surfaceKey,
            decoration: ShapeDecoration(
              color: t.red,
              shape: const CircleBorder(),
            ),
            child: const SizedBox.square(dimension: DotBadge.size),
          ),
        );
      },
    );
  }
}

/// 计数角标:高 16 的胶囊;出现、消失、数字变化都用 [AppMotion.pop]。
class CountBadge extends StatefulWidget {
  static const surfaceKey = ValueKey('count-badge-surface');

  final int count;
  final BadgeTone tone;

  const CountBadge({
    super.key,
    required this.count,
    this.tone = BadgeTone.alert,
  });

  @override
  State<CountBadge> createState() => _CountBadgeState();
}

class _CountBadgeState extends State<CountBadge>
    with SingleTickerProviderStateMixin {
  late final _scale = SingleMotionController(
    motion: AppMotion.pop,
    vsync: this,
    initialValue: widget.count > 0 ? 1 : 0,
  );

  /// 收起动画期间仍显示最后一个正数,不闪出 0
  late int _shown = widget.count;

  @override
  void didUpdateWidget(covariant CountBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.count == oldWidget.count) return;
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (widget.count > 0) {
      _shown = widget.count;
      if (reduced) {
        _scale.value = 1;
      } else {
        // 已显示时数字变化:从略小处弹回,新出现:从 0 弹出
        if (oldWidget.count > 0) _scale.value = .8;
        _scale.animateTo(1);
      }
    } else if (reduced) {
      _scale.value = 0;
    } else {
      _scale.animateTo(0);
    }
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final alert = widget.tone == BadgeTone.alert;
    return AnimatedBuilder(
      animation: _scale,
      builder: (context, _) {
        final scale = _scale.value.clamp(0.0, 2.0);
        if (scale == 0 || _shown <= 0) return const SizedBox.shrink();
        return Transform.scale(
          scale: scale,
          child: DecoratedBox(
            key: CountBadge.surfaceKey,
            decoration: BoxDecoration(
              color: alert ? t.red : t.text,
              borderRadius: BorderRadius.circular(8),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Center(
                  widthFactor: 1,
                  child: Text(
                    '$_shown',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      color: alert ? Colors.white : t.bg,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
