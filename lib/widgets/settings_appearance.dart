import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:motor/motor.dart';
import 'package:solar_icons/solar_icons.dart';

import '../core/appearance.dart';
import '../design/motion.dart';
import '../design/shapes.dart';
import '../design/theme.dart';
import '../design/theme_reveal.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../ui/chrome_button.dart';
import '../ui/press.dart';

/// 独立风格卡与页面上的明暗胶囊。
class SettingsAppearance extends StatefulWidget {
  final AppearanceController controller;
  const SettingsAppearance({super.key, required this.controller});

  @override
  State<SettingsAppearance> createState() => _SettingsAppearanceState();
}

class _SettingsAppearanceState extends State<SettingsAppearance> {
  Offset? _origin;

  void _change(VoidCallback change) {
    ThemeReveal.change(context, change, origin: _origin);
    _origin = null;
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final styles = AppearanceStyle.values;
    final modes = AppearanceMode.values;
    return Listener(
      onPointerDown: (event) => _origin = event.position,
      onPointerMove: (event) => _origin = event.position,
      onPointerCancel: (_) => _origin = null,
      onPointerUp: (_) =>
          WidgetsBinding.instance.addPostFrameCallback((_) => _origin = null),
      child: Padding(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            _StyleSelectorRow(
              styles: styles,
              selected: controller.style,
              showCinnabarDot: !controller.styleDotSeen,
              onSelect: (style) {
                if (style != controller.style) {
                  _change(() => controller.setStyle(style));
                }
              },
            ),
            const SizedBox(height: SettingsTokens.previewGap),
            _ModeSlideBar(
              modes: modes,
              selected: controller.mode,
              onSelect: (mode) {
                if (mode != controller.mode) {
                  _change(() => controller.set(mode));
                }
              },
            ),
          ],
        ),
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

  void _snapTo(int target, {double? velocity}) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _position.value = target.toDouble();
    } else {
      _position.animateTo(target.toDouble(), withVelocity: velocity);
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
    _snapTo(target, velocity: velocity);
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
    final selectedIndex = styles.indexOf(selected).clamp(0, styles.length - 1);
    return _SpringSlideTrack(
      count: styles.length,
      index: selectedIndex,
      gap: SettingsTokens.previewGap,
      onSelect: (index) => onSelect(styles[index]),
      builder: (context, position, itemWidth, step) => Row(
        children: [
          for (var i = 0; i < styles.length; i++) ...[
            if (i > 0) const SizedBox(width: SettingsTokens.previewGap),
            Expanded(
              child: StylePreviewCard(
                key: ValueKey('settings-style-${styles[i].name}'),
                style: styles[i],
                selected: selected == styles[i],
                emphasis: selected == styles[i] ? 1 : 0,
                dot: styles[i] == AppearanceStyle.cinnabar && showCinnabarDot,
                onTap: () {
                  if (selected == styles[i]) return;
                  HapticFeedback.selectionClick();
                  onSelect(styles[i]);
                },
              ),
            ),
          ],
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
    // Measure once per theme/text-scale change, outside the spring builder.
    final labelWidths = <double>[];
    for (final mode in modes) {
      final painter = TextPainter(
        text: TextSpan(text: mode.label, style: SettingsTokens.modeLabel),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      labelWidths.add(painter.width);
      painter.dispose();
    }
    return SizedBox(
      key: const ValueKey('settings-mode-track'),
      height: SettingsTokens.modeHeight,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: SettingsTokens.modeTrack(t),
          shape: appShape(AppRadii.full),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: SettingsTokens.modeInset,
          ),
          child: _SpringSlideTrack(
            count: modes.length,
            index: selectedIndex,
            onSelect: (index) => onSelect(modes[index]),
            builder: (context, position, itemWidth, step) => Stack(
              children: [
                Positioned(
                  left: 0,
                  top: SettingsTokens.modeInset,
                  bottom: SettingsTokens.modeInset,
                  width: itemWidth,
                  child: Transform.translate(
                    offset: Offset(position * step, 0),
                    child: IgnorePointer(
                      child: DecoratedBox(
                        key: const ValueKey('settings-mode-thumb'),
                        decoration: ShapeDecoration(
                          color: SettingsTokens.modeThumb(t),
                          shape: appShape(AppRadii.full),
                          shadows: SettingsTokens.thumbShadow(t),
                        ),
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
                          labelWidth: labelWidths[i],
                          selected: selected == modes[i],
                          emphasis: (1 - (position - i).abs()).clamp(0.0, 1.0),
                          onTap: () {
                            if (selected == modes[i]) return;
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
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  final AppearanceMode mode;
  final double labelWidth;
  final bool selected;
  final double emphasis;
  final VoidCallback onTap;

  const _ModeOption({
    required this.mode,
    required this.labelWidth,
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
        scale: AppPressScale.control,
        motion: AppMotion.entryTap,
        onTap: onTap,
        child: SizedBox(
          height: SettingsTokens.modeHeight,
          child: ExcludeSemantics(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final labelStyle = SettingsTokens.modeLabel.copyWith(
                  color: labelColor,
                );
                final showIcon = labelWidth + 28 <= constraints.maxWidth;
                return Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (showIcon) ...[
                          if (mode == AppearanceMode.system)
                            CustomPaint(
                              size: const Size.square(14),
                              painter: _SystemModeIcon(labelColor),
                            )
                          else
                            Icon(
                              mode == AppearanceMode.light
                                  ? SolarIconsBold.sun
                                  : SolarIconsBold.moon,
                              size: 16,
                              color: labelColor,
                            ),
                          const SizedBox(width: 6),
                        ],
                        Text(mode.label, style: labelStyle),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _SystemModeIcon extends CustomPainter {
  const _SystemModeIcon(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawArc(
      rect.deflate(1),
      1.5707963268,
      3.1415926536,
      true,
      Paint()..color = color,
    );
    canvas.drawOval(
      rect.deflate(1),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
  }

  @override
  bool shouldRepaint(_SystemModeIcon oldDelegate) => color != oldDelegate.color;
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
    this.emphasis = 1,
    required this.dot,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      selected: selected,
      child: PressScale(
        semanticLabel: style.label,
        scale: AppPressScale.card,
        onTap: onTap,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: t.surface,
            shape: appShape(SettingsTokens.cardRadius),
            shadows: SettingsTokens.cardShadow(t),
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(SettingsTokens.previewInset),
                child: ExcludeSemantics(
                  child: Column(
                    children: [
                      _StyleMiniature(style: style),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                style.label,
                                style: AppType.subhead.copyWith(
                                  color: t.text,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (dot) ...[
                              const SizedBox(width: 6),
                              Transform.translate(
                                offset: const Offset(0, -5),
                                child: DotBadge(visible: dot),
                              ),
                            ],
                            const Spacer(),
                            _StyleCheckBadge(selected: selected),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: selected ? 1 : 0),
                    duration: reduced ? AppMotion.reducedFade : AppMotion.fade,
                    builder: (context, opacity, _) => DecoratedBox(
                      key: ValueKey('settings-style-outline-${style.name}'),
                      decoration: ShapeDecoration(
                        shape: appShape(SettingsTokens.cardRadius).copyWith(
                          side: BorderSide(
                            color: t.accent.withValues(alpha: opacity),
                            width: SettingsTokens.selectionWidth,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StyleCheckBadge extends StatelessWidget {
  final bool selected;
  const _StyleCheckBadge({required this.selected});
  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return SizedBox.square(
      dimension: SettingsTokens.radioSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (!selected)
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: t.text3, width: 1.5),
              ),
              child: const SizedBox.expand(),
            ),
          SingleMotionBuilder(
            value: selected ? 1.0 : 0.0,
            motion: AppMotion.pop,
            active: !MediaQuery.disableAnimationsOf(context),
            builder: (context, value, _) => Transform.scale(
              scale: value.clamp(0.0, 2.0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: t.accent,
                  shape: BoxShape.circle,
                ),
                child: SizedBox.square(
                  dimension: SettingsTokens.radioSize,
                  child: Icon(
                    Icons.check_rounded,
                    size: 14,
                    color: SettingsTokens.strongForeground(t),
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

class _StyleMiniature extends StatelessWidget {
  final AppearanceStyle style;
  const _StyleMiniature({required this.style});
  @override
  Widget build(BuildContext context) {
    final t = tokensFor(Theme.of(context).brightness, style);
    final misty = style == AppearanceStyle.misty;
    Widget bar(Color color, double width, double height) => DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadii.bar),
      ),
      child: SizedBox(width: width, height: height),
    );
    return AppClip(
      radius: SettingsTokens.previewRadius,
      child: SizedBox(
        height: SettingsTokens.previewHeight,
        child: ColoredBox(
          color: t.grouped,
          child: Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 50,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: misty
                        ? LinearGradient(
                            colors: [
                              t.mistyBlue.withValues(alpha: .16),
                              t.mistyViolet.withValues(alpha: .12),
                            ],
                          )
                        : t.lacGradient,
                  ),
                ),
              ),
              if (!misty)
                Positioned(
                  top: 44,
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: t.grouped,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(SettingsTokens.logoRadius),
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 12,
                top: 15,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: t.warnBg,
                    shape: BoxShape.circle,
                  ),
                  child: const SizedBox.square(dimension: 15),
                ),
              ),
              Positioned(
                left: 33,
                top: 20,
                child: bar(misty ? t.text : t.onLac, 36, 5),
              ),
              Positioned(
                left: 10,
                right: 10,
                top: 38,
                height: 24,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: BorderRadius.circular(AppRadii.xs),
                    boxShadow: SettingsTokens.cardShadow(t),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        for (final color
                            in misty
                                ? [
                                    t.mistyBlue,
                                    t.mistyOrange,
                                    t.mistyGreen,
                                    t.mistyViolet,
                                  ]
                                : List.filled(4, t.accent))
                          bar(color, 5, 5),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 10,
                right: 10,
                top: 68,
                height: 24,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: BorderRadius.circular(AppRadii.xs),
                    boxShadow: SettingsTokens.cardShadow(t),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: bar(t.text.withValues(alpha: .28), 30, 4),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
