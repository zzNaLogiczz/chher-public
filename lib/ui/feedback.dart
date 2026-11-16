/// 反馈与状态:顶部提示条与整组骨架。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:motor/motor.dart';

import '../design/motion.dart';
import '../design/tokens.dart';
import '../design/typography.dart';

/// 深色胶囊提示条:从顶部安全区下方弹入,1.6 秒后淡出;新提示替换旧提示。
abstract final class AppToast {
  static const hold = Duration(milliseconds: 1600);
  static OverlayEntry? _current;

  static void show(BuildContext context, String message, {IconData? icon}) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _current?.remove();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ToastView(
        message: message,
        icon: icon,
        onDone: () {
          if (_current == entry) _current = null;
          if (entry.mounted) entry.remove();
        },
      ),
    );
    _current = entry;
    overlay.insert(entry);
  }
}

class _ToastView extends StatefulWidget {
  final String message;
  final IconData? icon;
  final VoidCallback onDone;
  const _ToastView({required this.message, this.icon, required this.onDone});

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView> with TickerProviderStateMixin {
  late final SingleMotionController _pop;
  late final AnimationController _life;

  @override
  void initState() {
    super.initState();
    _pop = SingleMotionController(
      motion: AppMotion.pop,
      vsync: this,
      initialValue: 0,
    );
    // 停留 + 淡出用同一条动画计时,期间按帧推进,结束即移除
    _life = AnimationController(
      vsync: this,
      duration: AppToast.hold + AppMotion.fade,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _pop.value = 1;
      } else {
        _pop.animateTo(1);
      }
      _life.forward().whenComplete(() {
        if (mounted) widget.onDone();
      });
    });
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
    final fadeStart =
        AppToast.hold.inMilliseconds /
        (AppToast.hold + AppMotion.fade).inMilliseconds;
    return Positioned(
      top: top + 8,
      left: 16,
      right: 16,
      child: IgnorePointer(
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
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xF01E1E20),
                borderRadius: BorderRadius.circular(AppRadii.full),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.icon != null) ...[
                        Icon(widget.icon, size: 18, color: Colors.white),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          widget.message,
                          maxLines: 3,
                          style: AppType.subhead.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                            decoration: TextDecoration.none,
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

/// Loading breathes as one cached layer; scroll and TickerMode stop hidden work.
class SkeletonPulse extends StatefulWidget {
  final bool active;
  final Widget child;
  const SkeletonPulse({super.key, this.active = true, required this.child});

  @override
  State<SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<SkeletonPulse>
    with SingleTickerProviderStateMixin {
  late final _clock = AnimationController(
    vsync: this,
    duration: AppMotion.skeletonDelay,
  )..addStatusListener(_status);
  final _bounds = GlobalKey();
  ScrollPosition? _position;
  Animation<double>? _routeAnimation;
  bool _waiting = true;
  bool _visible = false;
  bool _scheduled = false;
  bool _enabled = false;

  void _status(AnimationStatus status) {
    if (status == AnimationStatus.completed && _waiting) {
      setState(() => _waiting = false);
      _sync();
    }
  }

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
  void didUpdateWidget(covariant SkeletonPulse oldWidget) {
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
      if (_waiting) {
        _clock.forward();
      } else {
        _clock.repeat(period: AppMotion.skeletonCycle);
      }
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
        opacity: _waiting || !_enabled
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
                  child: ExcludeSemantics(
                    child: TickerMode(enabled: false, child: widget.skeleton),
                  ),
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
  const SkeletonList({super.key, this.rows = 6});

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
