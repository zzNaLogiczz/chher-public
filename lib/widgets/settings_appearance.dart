import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:motor/motor.dart';

import '../core/appearance.dart';
import '../design/icons.dart';
import '../design/motion.dart';
import '../design/shapes.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../ui/chrome_button.dart';
import '../ui/press.dart';

/// 风格画片和明暗模式共用一个平面设置分组。
class SettingsAppearance extends StatelessWidget {
  final AppearanceController controller;
  const SettingsAppearance({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final styles = AppearanceStyle.values;
    final modes = AppearanceMode.values;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          _StyleSelectorRow(
            styles: styles,
            selected: controller.style,
            showCinnabarDot: !controller.styleDotSeen,
            onSelect: controller.setStyle,
          ),
          const SizedBox(height: 10),
          _ModeSlideBar(
            modes: modes,
            selected: controller.mode,
            onSelect: controller.set,
          ),
        ],
      ),
    );
  }
}

/// 共享弹簧轨道：支持点击滑动与水平拖拽跟手切换。
class _SpringSlideTrack extends StatefulWidget {
  final int count;
  final int index;
  final double gap;
  final ValueChanged<int> onSelect;
  final Widget Function(
    BuildContext context,
    double position,
    double itemWidth,
    double step,
  )
  builder;

  const _SpringSlideTrack({
    required this.count,
    required this.index,
    this.gap = 0,
    required this.onSelect,
    required this.builder,
  });

  @override
  State<_SpringSlideTrack> createState() => _SpringSlideTrackState();
}

class _SpringSlideTrackState extends State<_SpringSlideTrack>
    with SingleTickerProviderStateMixin {
  late final SingleMotionController _position;
  bool _dragging = false;
  int _dragNotified = -1;

  @override
  void initState() {
    super.initState();
    _position = SingleMotionController(
      motion: AppMotion.select,
      vsync: this,
      initialValue: widget.index.toDouble(),
    );
  }

  @override
  void didUpdateWidget(covariant _SpringSlideTrack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging && oldWidget.index != widget.index) {
      _snapTo(widget.index);
    }
  }

  void _snapTo(int target) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _position.value = target.toDouble();
    } else {
      _position.animateTo(target.toDouble());
    }
  }

  void _onDragStart(DragStartDetails _) {
    _dragging = true;
    _dragNotified = widget.index;
    _position.stop();
  }

  void _onDragUpdate(DragUpdateDetails details, double step) {
    if (step <= 0) return;
    final next = (_position.value + (details.primaryDelta ?? 0) / step).clamp(
      0.0,
      (widget.count - 1).toDouble(),
    );
    _position.value = next;
    final nearest = next.round();
    if (nearest != _dragNotified) {
      _dragNotified = nearest;
      HapticFeedback.selectionClick();
    }
  }

  void _onDragEnd(DragEndDetails details, double step) {
    _dragging = false;
    final velocity = step > 0 ? (details.primaryVelocity ?? 0) / step : 0.0;
    final rawTarget = velocity.abs() > 0.65
        ? (velocity > 0
              ? (_position.value + 0.25).ceil()
              : (_position.value - 0.25).floor())
        : _position.value.round();
    final target = rawTarget.clamp(0, widget.count - 1);
    if (target != widget.index) {
      if (_dragNotified != target) HapticFeedback.selectionClick();
      widget.onSelect(target);
    }
    _snapTo(target);
  }

  void _onDragCancel() {
    _dragging = false;
    _snapTo(widget.index);
  }

  @override
  void dispose() {
    _position.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final totalGap = widget.gap * (widget.count - 1);
      final itemWidth = (constraints.maxWidth - totalGap) / widget.count;
      final step = itemWidth + widget.gap;
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: _onDragStart,
        onHorizontalDragUpdate: (d) => _onDragUpdate(d, step),
        onHorizontalDragEnd: (d) => _onDragEnd(d, step),
        onHorizontalDragCancel: _onDragCancel,
        child: AnimatedBuilder(
          animation: _position,
          builder: (context, _) =>
              widget.builder(context, _position.value, itemWidth, step),
        ),
      );
    },
  );
}

class _StyleSelectorRow extends StatelessWidget {
  final List<AppearanceStyle> styles;
  final AppearanceStyle selected;
  final bool showCinnabarDot;
  final ValueChanged<AppearanceStyle> onSelect;

  const _StyleSelectorRow({
    required this.styles,
    required this.selected,
    required this.showCinnabarDot,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final selectedIndex = styles.indexOf(selected).clamp(0, styles.length - 1);
    return _SpringSlideTrack(
      count: styles.length,
      index: selectedIndex,
      gap: 10,
      onSelect: (index) => onSelect(styles[index]),
      builder: (context, position, itemWidth, step) => Stack(
        children: [
          Positioned.fill(
            child: Row(
              children: [
                for (var i = 0; i < styles.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        color: t.fill3,
                        shape: appShape(AppRadii.sm),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Positioned(
            left: position * step,
            top: 0,
            bottom: 0,
            width: itemWidth,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  color: t.accentFill,
                  shape: appShape(AppRadii.sm).copyWith(
                    side: BorderSide(color: t.accent, width: 1.5),
                  ),
                  shadows: t.shadowE1,
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (var i = 0; i < styles.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: StylePreviewCard(
                    key: ValueKey('settings-style-${styles[i].name}'),
                    style: styles[i],
                    selected: selected == styles[i],
                    emphasis: (1 - (position - i).abs()).clamp(0.0, 1.0),
                    dot:
                        styles[i] == AppearanceStyle.cinnabar &&
                        showCinnabarDot,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onSelect(styles[i]);
                    },
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ModeSlideBar extends StatelessWidget {
  final List<AppearanceMode> modes;
  final AppearanceMode selected;
  final ValueChanged<AppearanceMode> onSelect;

  const _ModeSlideBar({
    required this.modes,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final selectedIndex = modes.indexOf(selected).clamp(0, modes.length - 1);
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: t.fill,
        shape: appShape(AppRadii.full),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: _SpringSlideTrack(
          count: modes.length,
          index: selectedIndex,
          onSelect: (index) => onSelect(modes[index]),
          builder: (context, position, itemWidth, step) => Stack(
            children: [
              Positioned(
                left: position * step,
                top: 0,
                bottom: 0,
                width: itemWidth,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: t.segmentedThumb,
                      shape: appShape(AppRadii.full),
                      shadows: t.shadowE1,
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < modes.length; i++)
                    Expanded(
                      child: _ModeOption(
                        mode: modes[i],
                        selected: selected == modes[i],
                        emphasis: (1 - (position - i).abs()).clamp(0.0, 1.0),
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onSelect(modes[i]);
                        },
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  final AppearanceMode mode;
  final bool selected;
  final double emphasis;
  final VoidCallback onTap;

  const _ModeOption({
    required this.mode,
    required this.selected,
    required this.emphasis,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final labelColor = Color.lerp(t.text2, t.text, emphasis)!;
    return Semantics(
      selected: selected,
      child: PressScale(
        key: ValueKey('settings-mode-${mode.name}'),
        semanticLabel: mode.label,
        scale: .94,
        motion: AppMotion.entryTap,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: ExcludeSemantics(
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    mode.label,
                    style: AppType.footnote.copyWith(
                      color: labelColor,
                      fontWeight: emphasis > 0.5
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class StylePreviewCard extends StatelessWidget {
  final AppearanceStyle style;
  final bool selected;
  final double emphasis;
  final bool dot;
  final VoidCallback onTap;
  const StylePreviewCard({
    super.key,
    required this.style,
    required this.selected,
    this.emphasis = 1.0,
    required this.dot,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final e = emphasis.clamp(0.0, 1.0);
    final labelColor = Color.lerp(t.text2, t.text, e)!;
    return Semantics(
      selected: selected,
      child: PressScale(
        semanticLabel: style.label,
        scale: .94,
        motion: AppMotion.entryTap,
        onTap: onTap,
        child: Padding(
          // 外框 AppRadii.sm (12) - 4dp 边距 = AppRadii.xs (8) 严格同心曲率
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 9),
          child: ExcludeSemantics(
            child: Column(
              children: [
                Transform.scale(
                  scale: 0.965 + 0.035 * e,
                  child: _StyleMiniature(style: style),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          style.label,
                          style: AppType.subhead.copyWith(
                            color: labelColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (dot) ...[
                        const DotBadge(visible: true),
                        const SizedBox(width: 5),
                      ],
                      _StyleCheckBadge(emphasis: e),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StyleCheckBadge extends StatelessWidget {
  final double emphasis;
  const _StyleCheckBadge({required this.emphasis});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final e = emphasis.clamp(0.0, 1.0);
    return SizedBox.square(
      dimension: 18,
      child: Stack(
        alignment: Alignment.center,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Color.lerp(
                  t.separator.withValues(alpha: .65),
                  t.accent,
                  e,
                )!,
                width: 1.5,
              ),
            ),
            child: const SizedBox.expand(),
          ),
          if (e > 0.01)
            Transform.scale(
              scale: e,
              child: Opacity(
                opacity: e,
                child: Icon(AppIcons.success, size: 18, color: t.accent),
              ),
            ),
        ],
      ),
    );
  }
}

class _StyleMiniature extends StatelessWidget {
  final AppearanceStyle style;
  const _StyleMiniature({required this.style});

  @override
  Widget build(BuildContext context) {
    final darkT = (1.0 - AppTokens.of(context).bg.computeLuminance()).clamp(
      0.0,
      1.0,
    );
    final t = tokensFor(
      Brightness.light,
      style,
    ).lerp(tokensFor(Brightness.dark, style), darkT);
    final misty = style == AppearanceStyle.misty;
    Widget bar(Color color, double width) => Container(
      width: width,
      height: 3.5,
      decoration: ShapeDecoration(
        color: color,
        shape: appShape(AppRadii.bar),
      ),
    );
    Widget tray(Color background, List<Color> dots) => Container(
      height: 11,
      decoration: ShapeDecoration(
        color: background,
        shape: appShape(AppRadii.bar),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [for (final c in dots) bar(c, 4)],
      ),
    );
    return AppClip(
      radius: AppRadii.xs,
      child: Container(
        height: 70,
        color: misty ? t.grouped : t.bg,
        child: misty
            ? Column(
                children: [
                  Container(
                    height: 19,
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    color: t.surface,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [bar(t.text, 18), bar(t.accent, 4.5)],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 5,
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(3.5),
                      decoration: ShapeDecoration(
                        color: t.surface,
                        shape: appShape(AppRadii.xs),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              bar(t.accent.withValues(alpha: .28), 6),
                              const SizedBox(width: 4),
                              bar(t.text, 20),
                            ],
                          ),
                          const SizedBox(height: 4),
                          tray(t.mistyTray, [
                            t.mistyBlue,
                            t.mistyOrange,
                            t.mistyGreen,
                            t.mistyViolet,
                          ]),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : Stack(
                children: [
                  Container(
                    height: 32,
                    padding: const EdgeInsets.fromLTRB(7, 5, 7, 0),
                    color: t.lacMid,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        bar(t.onLac, 18),
                        const SizedBox(height: 5),
                        tray(t.lacRecess, [
                          t.onLac,
                          t.onLac,
                          t.onLac,
                          t.onLac,
                        ]),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 27,
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(7, 6, 7, 0),
                      decoration: ShapeDecoration(
                        color: t.grouped,
                        shape: appShape(AppRadii.xs),
                      ),
                      alignment: Alignment.topCenter,
                      child: Container(
                        height: 16,
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        decoration: ShapeDecoration(
                          color: t.surface,
                          shape: appShape(AppRadii.xs),
                        ),
                        child: Row(
                          children: [
                            bar(t.accentFill2, 6),
                            const SizedBox(width: 4),
                            Flexible(child: bar(t.text3, 28)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
