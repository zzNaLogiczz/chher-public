/// 反馈与状态:顶部提示条与整组骨架。
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:motor/motor.dart';

import '../design/feedback.dart';
import '../design/icons.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import 'press.dart';

/// 深色胶囊提示条从顶部安全区下方弹入。新提示替换旧提示。
abstract final class AppToast {
  static const hold = Duration(milliseconds: 1600);
  static OverlayEntry? _current;

  static void show(
    BuildContext context,
    String message, {
    IconData? icon,
    String? actionLabel,
    VoidCallback? onAction,
    Color? actionColor,
  }) {
    assert((actionLabel == null) == (onAction == null));
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _current?.remove();
    late final OverlayEntry entry;
    void dismiss() {
      if (_current != entry) return;
      _current = null;
      if (entry.mounted) entry.remove();
    }

    entry = OverlayEntry(
      builder: (_) => _ToastView(
        message: message,
        icon: icon,
        actionLabel: onAction == null ? null : actionLabel,
        actionColor: actionColor,
        onAction: actionLabel == null || onAction == null
            ? null
            : () {
                if (_current != entry) return;
                dismiss();
                onAction();
              },
        onDone: dismiss,
      ),
    );
    _current = entry;
    overlay.insert(entry);
  }
}

class _ToastView extends StatefulWidget {
  final String message;
  final IconData? icon;
  final String? actionLabel;
  final Color? actionColor;
  final VoidCallback? onAction;
  final VoidCallback onDone;
  const _ToastView({
    required this.message,
    this.icon,
    this.actionLabel,
    this.actionColor,
    this.onAction,
    required this.onDone,
  });

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView> with TickerProviderStateMixin {
  late final SingleMotionController _pop;
  late final AnimationController _life;
  late final _hold = widget.onAction == null
      ? AppToast.hold
      : const Duration(seconds: 6);
  final _holdingPointers = <int>{};

  double get _fadeStart =>
      _hold.inMicroseconds / _life.duration!.inMicroseconds;

  @override
  void initState() {
    super.initState();
    _pop = SingleMotionController(
      motion: AppMotion.pop,
      vsync: this,
      initialValue: 0,
    );
    // 停留 + 淡出用同一条动画计时,期间按帧推进,结束即移除
    _life =
        AnimationController(
          vsync: this,
          duration: _hold + AppMotion.fade,
          animationBehavior: AnimationBehavior.preserve,
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) widget.onDone();
        });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _pop.value = 1;
      } else {
        _pop.animateTo(1);
      }
      _life.forward();
    });
  }

  void _pause(PointerDownEvent event) {
    if (_life.isCompleted) return;
    _holdingPointers.add(event.pointer);
    _life.stop();
    if (_life.value > _fadeStart) _life.value = _fadeStart;
  }

  void _resume(PointerEvent event) {
    if (mounted &&
        _holdingPointers.remove(event.pointer) &&
        _holdingPointers.isEmpty) {
      _life.forward();
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    _life.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final fadeStart = _fadeStart;
    final actionLabel = widget.actionLabel;
    return Positioned(
      top: top + 8,
      left: 16,
      right: 16,
      child: IgnorePointer(
        ignoring: actionLabel == null,
        child: Center(
          child: AnimatedBuilder(
            animation: Listenable.merge([_pop, _life]),
            builder: (context, child) {
              final p = _pop.value;
              final fade = _life.value <= fadeStart
                  ? 1.0
                  : 1 - (_life.value - fadeStart) / (1 - fadeStart);
              return Opacity(
                opacity: (p.clamp(0.0, 1.0) * fade).clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(0, -24 * (1 - p)),
                  child: child,
                ),
              );
            },
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: actionLabel == null ? null : _pause,
              onPointerUp: _resume,
              onPointerCancel: _resume,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: ToastColors.ink.withAlpha(0xF0),
                  borderRadius: BorderRadius.circular(AppRadii.full),
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: actionLabel == null ? 44 : 52,
                  ),
                  child: Padding(
                    padding: actionLabel == null
                        ? const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 10,
                          )
                        : const EdgeInsets.fromLTRB(16, 4, 6, 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.icon != null) ...[
                          Icon(widget.icon, size: 18, color: Radix.whiteA12),
                          const SizedBox(width: 8),
                        ],
                        Flexible(
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              vertical: actionLabel == null ? 0 : 2,
                            ),
                            child: Text(
                              widget.message,
                              maxLines: 3,
                              style: AppType.subhead.copyWith(
                                color: Radix.whiteA12,
                                fontWeight: FontWeight.w500,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        ),
                        if (actionLabel != null) ...[
                          const SizedBox(width: 8),
                          Flexible(child: _buildAction(actionLabel)),
                        ],
                      ],
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

  Widget _buildAction(String label) {
    const height = 40.0;
    const hitHeight = FeedbackMetrics.touchTarget;
    final background = widget.actionColor;
    final foreground = background == null ? ToastColors.ink : Radix.whiteA12;
    return PressScale(
      onTap: widget.onAction,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: (hitHeight - height) / 2),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background ?? Radix.whiteA12.withValues(alpha: .96),
            borderRadius: BorderRadius.circular(height / 2),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: hitHeight,
              minHeight: height,
            ),
            child: Padding(
              padding: const EdgeInsets.only(left: 15, right: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: AppType.subhead.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(AppIcons.forward, size: 12, color: foreground),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Reserve the waiting layout without flashing a placeholder for fast reads.
/// This never delays data: removing the widget cancels the one-shot timer.
class LoadingPlaceholder extends StatefulWidget {
  final bool active;
  final Widget child;
  final VoidCallback? onVisible;
  const LoadingPlaceholder({
    super.key,
    this.active = true,
    this.onVisible,
    required this.child,
  });

  @override
  State<LoadingPlaceholder> createState() => _LoadingPlaceholderState();
}

class _LoadingPlaceholderState extends State<LoadingPlaceholder> {
  Timer? _delay;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _wait();
  }

  void _wait() {
    if (!widget.active) return;
    _delay = Timer(AppMotion.skeletonDelay, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void didUpdateWidget(covariant LoadingPlaceholder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == oldWidget.active) return;
    _delay?.cancel();
    _visible = false;
    _wait();
  }

  @override
  void dispose() {
    _delay?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible && widget.active;
    if (visible) widget.onVisible?.call();
    return Visibility(
      visible: visible,
      maintainState: true,
      maintainAnimation: true,
      maintainSize: true,
      child: TickerMode(
        enabled: visible,
        child: IgnorePointer(child: widget.child),
      ),
    );
  }
}

/// Loading breathes as one cached layer; scroll and TickerMode stop hidden work.
class SkeletonPulse extends StatelessWidget {
  final bool active;
  final bool immediate;
  final Widget child;
  final VoidCallback? onVisible;
  const SkeletonPulse({
    super.key,
    this.active = true,
    this.immediate = false,
    this.onVisible,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final breath = _SkeletonBreath(active: active, child: child);
    return immediate
        ? breath
        : LoadingPlaceholder(
            active: active,
            onVisible: onVisible,
            child: breath,
          );
  }
}

class _SkeletonBreath extends StatefulWidget {
  final bool active;
  final Widget child;
  const _SkeletonBreath({required this.active, required this.child});

  @override
  State<_SkeletonBreath> createState() => _SkeletonBreathState();
}

class _SkeletonBreathState extends State<_SkeletonBreath>
    with SingleTickerProviderStateMixin {
  late final _clock = AnimationController(
    vsync: this,
    duration: AppMotion.skeletonCycle,
  );
  final _bounds = GlobalKey();
  ScrollPosition? _position;
  Animation<double>? _routeAnimation;
  bool _visible = false;
  bool _scheduled = false;
  bool _enabled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final routeAnimation = ModalRoute.of(context)?.animation;
    if (routeAnimation != _routeAnimation) {
      _routeAnimation?.removeListener(_checkAfterLayout);
      _routeAnimation = routeAnimation;
      _routeAnimation?.addListener(_checkAfterLayout);
    }
    final position = Scrollable.maybeOf(context)?.position;
    if (position != _position) {
      _position?.removeListener(_checkAfterLayout);
      _position = position;
      _position?.addListener(_checkAfterLayout);
    }
    _enabled =
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    _sync();
    _checkAfterLayout();
  }

  @override
  void didUpdateWidget(covariant _SkeletonBreath oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _checkAfterLayout() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final box = _bounds.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      final bounds = box.localToGlobal(Offset.zero) & box.size;
      var visible = bounds.overlaps(Offset.zero & MediaQuery.sizeOf(context));
      final RenderObject? viewport = RenderAbstractViewport.maybeOf(box);
      if (viewport is RenderBox && viewport.hasSize) {
        visible =
            visible &&
            bounds.overlaps(
              viewport.localToGlobal(Offset.zero) & viewport.size,
            );
      }
      _visible = visible;
      _sync();
    });
  }

  void _sync() {
    if (!widget.active || !_enabled || !_visible) {
      _clock.stop();
    } else if (!_clock.isAnimating) {
      _clock.repeat(period: AppMotion.skeletonCycle);
    }
  }

  @override
  void dispose() {
    _position?.removeListener(_checkAfterLayout);
    _routeAnimation?.removeListener(_checkAfterLayout);
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    key: _bounds,
    child: AnimatedBuilder(
      animation: _clock,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: !_enabled
            ? 1
            : AppMotion.skeletonMinOpacity +
                  (1 - AppMotion.skeletonMinOpacity) *
                      (1 + math.cos(_clock.value * math.pi * 2)) /
                      2,
        child: child,
      ),
    ),
  );
}

/// The incoming layout is fixed immediately; only its paint crossfades.
class SkeletonContent extends StatefulWidget {
  final bool loading;
  final Color? background;
  final Widget skeleton;
  final Widget child;
  const SkeletonContent({
    super.key,
    required this.loading,
    this.background,
    required this.skeleton,
    required this.child,
  });

  @override
  State<SkeletonContent> createState() => _SkeletonContentState();
}

class _SkeletonContentState extends State<SkeletonContent>
    with SingleTickerProviderStateMixin {
  late final _arrival =
      AnimationController(
        vsync: this,
        duration: AppMotion.fade,
        value: widget.loading ? 0 : 1,
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed) setState(() {});
      });

  @override
  void didUpdateWidget(covariant SkeletonContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.loading == oldWidget.loading) return;
    if (widget.loading) {
      _arrival.value = 0;
    } else {
      _arrival.duration = MediaQuery.disableAnimationsOf(context)
          ? AppMotion.reducedFade
          : AppMotion.fade;
      _arrival.forward();
    }
  }

  @override
  void dispose() {
    _arrival.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      widget.loading
          ? SkeletonPulse(
              child: TickerMode(enabled: false, child: widget.skeleton),
            )
          : widget.child,
      if (!widget.loading && !_arrival.isCompleted)
        Positioned.fill(
          child: IgnorePointer(
            child: FadeTransition(
              opacity: ReverseAnimation(_arrival),
              child: RepaintBoundary(
                child: ColoredBox(
                  color: widget.background ?? AppTokens.of(context).bg,
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

/// 列表首屏骨架:整组呼吸,不逐条重画。
class SkeletonList extends StatelessWidget {
  final int rows;
  final VoidCallback? onVisible;
  const SkeletonList({super.key, this.rows = 6, this.onVisible});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    Widget bar(double widthFactor, double height) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: widthFactor,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: t.fill,
            borderRadius: BorderRadius.circular(AppRadii.xs),
          ),
          child: SizedBox(height: height),
        ),
      ),
    );
    return SkeletonPulse(
      onVisible: onVisible,
      child: Semantics(
        label: '加载中',
        child: ClipRect(
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              AppSpace.screen,
              16,
              AppSpace.screen,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < rows; i++) ...[
                  bar(.28, 12),
                  bar(.9, 16),
                  bar(.5, 12),
                  const SizedBox(height: 18),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
