/// Shared compact mode selector for forum and article comments.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:solar_icons/solar_icons.dart';

import '../core/reading_prefs.dart';
import '../design/loading_tokens.dart';
import '../design/message_tokens.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import 'expressive_controls.dart' show ActionFocusRing;
import 'chhers_loader.dart';
export '../core/reading_prefs.dart' show CommentViewMode;

/// A bounded width is the space left after the heading, count and 12dp gap.
/// Only this repaint boundary rebuilds while the shared progress spring moves.
class CommentModeBar extends StatefulWidget {
  final CommentViewMode mode;
  final ValueChanged<CommentViewMode> onChanged;
  final String authorLabel;
  final bool showAuthor;

  const CommentModeBar({
    super.key,
    required this.mode,
    required this.onChanged,
    this.authorLabel = '楼主',
    this.showAuthor = true,
  });

  @override
  State<CommentModeBar> createState() => _CommentModeBarState();
}

class _CommentModeBarState extends State<CommentModeBar>
    with TickerProviderStateMixin {
  late final _progress = AnimationController.unbounded(
    vsync: this,
    value: _index.toDouble(),
  );
  late final _fade = AnimationController(
    vsync: this,
    value: 1,
    duration: AppMotion.reducedFade,
  );
  late int _target = _index;
  bool _reduced = false;
  TextScaler? _textScaler;
  TextDirection? _direction;
  List<double>? _labelWidths;
  double _dragX = 0;
  double _dragProgress = 0;

  int get _count => widget.showAuthor ? 3 : 2;
  int get _index =>
      CommentViewMode.values.indexOf(widget.mode).clamp(0, _count - 1);
  List<String> get _labels => [
    '评论',
    '楼层',
    if (widget.showAuthor) widget.authorLabel,
  ];
  static const _icons = [
    SolarIconsOutline.dialog,
    SolarIconsOutline.sortByTime,
    SolarIconsOutline.userSpeakRounded,
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced && !_reduced) _progress.value = _target.toDouble();
    _reduced = reduced;
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    if (scaler != _textScaler || direction != _direction) {
      _textScaler = scaler;
      _direction = direction;
      _labelWidths = null;
    }
  }

  @override
  void didUpdateWidget(CommentModeBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authorLabel != widget.authorLabel ||
        oldWidget.showAuthor != widget.showAuthor) {
      _labelWidths = null;
    }
    if (oldWidget.mode != widget.mode ||
        oldWidget.showAuthor != widget.showAuthor) {
      _settle(_index);
    }
  }

  void _settle(int target, {double? velocity}) {
    final changed = target != _target;
    _target = target;
    AppMotion.settle(
      _progress,
      target: target.toDouble(),
      motion: AppMotion.select,
      velocity: velocity,
      reduced: _reduced,
    );
    if (_reduced && changed) _fade.forward(from: 0);
  }

  void _select(int target, {double? velocity}) {
    final changed = target != _target;
    _settle(target, velocity: velocity);
    if (changed) {
      HapticFeedback.selectionClick();
      widget.onChanged(CommentViewMode.values[target]);
    }
  }

  void _dragTo(double x, double step) {
    var p = _dragProgress + (x - _dragX) / step;
    if (p < 0) p *= CommentModeTokens.overscrollResistance;
    if (p > _count - 1) {
      p =
          _count -
          1 +
          (p - (_count - 1)) * CommentModeTokens.overscrollResistance;
    }
    _progress.value = p;
  }

  List<double> _measureLabels() => _labelWidths ??= _labels.map((label) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: CommentModeTokens.labelStyle),
      textDirection: _direction,
      textScaler: _textScaler!,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }).toList();

  @override
  void dispose() {
    _progress.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final widths = _measureLabels();
    final segmentWidths = widths
        .map(
          (labelWidth) =>
              labelWidth +
              CommentModeTokens.leading +
              CommentModeTokens.iconSize +
              CommentModeTokens.labelGap +
              CommentModeTokens.trailing,
        )
        .toList();
    const insets = 2 * CommentModeTokens.inset;
    final fullWidth = segmentWidths.reduce((a, b) => a + b) + insets;
    final compactWidth =
        segmentWidths.reduce(math.max) +
        (_count - 1) * CommentModeTokens.minimumSegment +
        insets;
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final allLabels = fullWidth <= constraints.maxWidth;
          final iconsOnly = compactWidth > constraints.maxWidth;
          final width = allLabels
              ? fullWidth
              : iconsOnly
              ? _count * CommentModeTokens.iconSegment + insets
              : compactWidth;
          final geometry = _ModeGeometry(
            widths,
            width,
            iconsOnly,
            allLabels ? segmentWidths : null,
          );
          final step = (width - insets) / _count;
          return Align(
            alignment: Alignment.centerRight,
            widthFactor: 1,
            heightFactor: 1,
            child: SizedBox(
              width: width,
              height: CommentModeTokens.hitHeight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragDown: (details) {
                  _dragX = details.localPosition.dx;
                  final p = _progress.value;
                  // Undo resistance before catching an in-flight overshoot.
                  _dragProgress = p < 0
                      ? p / CommentModeTokens.overscrollResistance
                      : p > _count - 1
                      ? _count -
                            1 +
                            (p - (_count - 1)) /
                                CommentModeTokens.overscrollResistance
                      : p;
                  _progress.stop();
                },
                onHorizontalDragStart: (details) =>
                    _dragTo(details.localPosition.dx, step),
                onHorizontalDragUpdate: (details) =>
                    _dragTo(details.localPosition.dx, step),
                onHorizontalDragEnd: (details) {
                  final velocity = (details.velocity.pixelsPerSecond.dx / step)
                      .clamp(
                        -CommentModeTokens.velocityLimit,
                        CommentModeTokens.velocityLimit,
                      );
                  final target =
                      (_progress.value +
                              velocity * CommentModeTokens.projectionSeconds)
                          .round()
                          .clamp(0, _count - 1);
                  _select(target, velocity: velocity);
                },
                onHorizontalDragCancel: () => _settle(_target),
                child: AnimatedBuilder(
                  animation: Listenable.merge([_progress, _fade]),
                  builder: (context, _) {
                    final p = _progress.value;
                    final segments = geometry.at(p);
                    final thumb = geometry.thumb(p);
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: 0,
                          right: 0,
                          top:
                              (CommentModeTokens.hitHeight -
                                  CommentModeTokens.trackHeight) /
                              2,
                          height: CommentModeTokens.trackHeight,
                          child: DecoratedBox(
                            key: const ValueKey('comment-mode-track'),
                            decoration: BoxDecoration(
                              color: t.isDark
                                  ? t.surface
                                  : MessageTokens.standardTrack(t, false),
                              borderRadius: BorderRadius.circular(
                                CommentModeTokens.trackHeight / 2,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: thumb.$1,
                          width: thumb.$2,
                          top:
                              (CommentModeTokens.hitHeight -
                                  CommentModeTokens.thumbHeight) /
                              2,
                          height: CommentModeTokens.thumbHeight,
                          child: DecoratedBox(
                            key: const ValueKey('comment-mode-thumb'),
                            decoration: BoxDecoration(
                              color: MessageTokens.standardThumb(t, false),
                              borderRadius: BorderRadius.circular(
                                CommentModeTokens.thumbHeight / 2,
                              ),
                              boxShadow: MessageTokens.standardShadow(t, false),
                            ),
                          ),
                        ),
                        for (var i = 0; i < _count; i++)
                          Positioned(
                            left: segments[i].$1,
                            width: segments[i].$2,
                            top: 0,
                            height: CommentModeTokens.hitHeight,
                            child: _ModeSegment(
                              key: ValueKey('comment-mode-$i'),
                              label: _labels[i],
                              icon: _icons[i],
                              selected: i == _target,
                              labelWidth: widths[i],
                              labelShift: geometry.labelShift(
                                segments[i],
                                widths[i],
                                allLabels ? 1 : _emphasis(p, i),
                              ),
                              iconsOnly: iconsOnly,
                              emphasis: _emphasis(p, i),
                              reveal: allLabels ? 1 : _emphasis(p, i),
                              fade: _reduced && i == _target ? _fade.value : 1,
                              onTap: () => _select(i),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

double _emphasis(double progress, int index) {
  final x = (1 - (progress - index).abs() / CommentModeTokens.labelReach).clamp(
    0.0,
    1.0,
  );
  return x * x * (3 - 2 * x);
}

/// All segment frames and the thumb interpolate between the same two layouts.
class _ModeGeometry {
  final List<double> labels;
  final double width;
  final bool iconsOnly;
  final List<double>? fixedWidths;
  late final states = List.generate(labels.length, (selected) {
    final selectedWidth = iconsOnly
        ? CommentModeTokens.iconSegment
        : CommentModeTokens.leading +
              CommentModeTokens.iconSize +
              CommentModeTokens.labelGap +
              labels[selected] +
              CommentModeTokens.trailing;
    final rest =
        (width - 2 * CommentModeTokens.inset - selectedWidth) /
        (labels.length - 1);
    var x = CommentModeTokens.inset;
    return List.generate(labels.length, (i) {
      final w = fixedWidths?[i] ?? (i == selected ? selectedWidth : rest);
      final frame = (x, w);
      x += w;
      return frame;
    });
  });
  _ModeGeometry(this.labels, this.width, this.iconsOnly, this.fixedWidths);

  (int, int, double) _interval(double p) {
    final q = p.clamp(0.0, labels.length - 1.0);
    final a = math.min(q.floor(), labels.length - 2);
    return (a, a + 1, q - a);
  }

  (double, double) _lerp((double, double) a, (double, double) b, double f) =>
      (a.$1 + (b.$1 - a.$1) * f, a.$2 + (b.$2 - a.$2) * f);
  List<(double, double)> at(double p) {
    final (a, b, f) = _interval(p);
    return List.generate(
      labels.length,
      (i) => _lerp(states[a][i], states[b][i], f),
    );
  }

  // Preserve whole glyphs while their layout footprint closes. Translate the
  // fading label inward at track edges instead of clipping half a character.
  double labelShift(
    (double, double) segment,
    double labelWidth,
    double reveal,
  ) {
    if (iconsOnly) return 0;
    final footprint =
        CommentModeTokens.iconSize +
        (labelWidth + CommentModeTokens.labelGap) * reveal;
    final start =
        segment.$1 +
        (segment.$2 - footprint) / 2 +
        CommentModeTokens.iconSize +
        CommentModeTokens.labelGap;
    return start.clamp(
          CommentModeTokens.inset,
          width - CommentModeTokens.inset - labelWidth,
        ) -
        start;
  }

  (double, double) thumb(double p) {
    final (a, b, f) = _interval(p);
    var (x, w) = _lerp(states[a][a], states[b][b], f);
    final over = p < 0 ? -p : math.max(0.0, p - (labels.length - 1));
    final shrink =
        w *
        math.min(
          CommentModeTokens.maxShrink,
          over * CommentModeTokens.overscrollShrink,
        );
    if (p > labels.length - 1) x += shrink;
    w -= shrink;
    return (x, w);
  }
}

class _ModeSegment extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final bool iconsOnly;
  final double labelWidth;
  final double labelShift;
  final double emphasis;
  final double reveal;
  final double fade;
  final VoidCallback onTap;
  const _ModeSegment({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.iconsOnly,
    required this.labelWidth,
    required this.labelShift,
    required this.emphasis,
    required this.reveal,
    required this.fade,
    required this.onTap,
  });
  @override
  State<_ModeSegment> createState() => _ModeSegmentState();
}

class _ModeSegmentState extends State<_ModeSegment>
    with SingleTickerProviderStateMixin {
  late final _press = AnimationController.unbounded(vsync: this, value: 1);
  bool _focused = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _press.value = 1;
  }

  void _pressed(bool down) => AppMotion.settle(
    _press,
    target: down && !MediaQuery.disableAnimationsOf(context)
        ? CommentModeTokens.iconPressScale
        : 1,
    motion: AppMotion.tap,
    reduced: MediaQuery.disableAnimationsOf(context),
  );
  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final color = Color.lerp(t.text2, t.text, widget.emphasis)!;
    final reveal = widget.reveal;
    return Semantics(
      label: widget.label,
      button: true,
      selected: widget.selected,
      onTap: widget.onTap,
      excludeSemantics: true,
      child: Tooltip(
        message: widget.label,
        excludeFromSemantics: true,
        child: FocusableActionDetector(
          onShowFocusHighlight: (value) => setState(() => _focused = value),
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          },
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onTap();
                return null;
              },
            ),
          },
          child: ActionFocusRing(
            visible: _focused,
            child: Listener(
              onPointerDown: (_) => _pressed(true),
              onPointerUp: (_) => _pressed(false),
              onPointerCancel: (_) => _pressed(false),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onTap,
                onTapCancel: () => _pressed(false),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedBuilder(
                        animation: _press,
                        builder: (context, child) =>
                            Transform.scale(scale: _press.value, child: child),
                        child: Icon(
                          widget.icon,
                          size: CommentModeTokens.iconSize,
                          color: color,
                        ),
                      ),
                      if (!widget.iconsOnly)
                        SizedBox(
                          width:
                              (widget.labelWidth + CommentModeTokens.labelGap) *
                              reveal,
                          child: OverflowBox(
                            alignment: Alignment.centerLeft,
                            minWidth:
                                widget.labelWidth + CommentModeTokens.labelGap,
                            maxWidth:
                                widget.labelWidth + CommentModeTokens.labelGap,
                            child: Padding(
                              padding: const EdgeInsets.only(
                                left: CommentModeTokens.labelGap,
                              ),
                              child: Transform.translate(
                                offset: Offset(widget.labelShift, 0),
                                child: Text(
                                  widget.label,
                                  maxLines: 1,
                                  softWrap: false,
                                  style: CommentModeTokens.labelStyle.copyWith(
                                    color: color.withValues(
                                      alpha: reveal * widget.fade,
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
            ),
          ),
        ),
      ),
    );
  }
}

/// 计数位置上的等待指示:切换方式读取网络期间代替旧计数
class CommentModeBusy extends StatelessWidget {
  const CommentModeBusy({super.key});

  @override
  Widget build(BuildContext context) {
    return const Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: ChhersSpinner(size: LoadingTokens.input),
          ),
        ],
      ),
      style: AppType.footnote,
    );
  }
}
