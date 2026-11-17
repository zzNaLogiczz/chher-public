/// 门户卡片展开与阅读页直接拖动使用独立的动画通道。
///
/// 只有顶部手柄接入 begin/update/endDismiss，正文保留原生纵向滚动。
/// update 的增量为 dy / 屏高，end 的速度为每秒 dy / 屏高。
/// 拖动阶段页面整体一比一跟手；确认关闭后才由 Navigator 普通 pop
/// 触发 Hero 从当前全局矩形收回，取消不会提前把 Hero 飞回首页。
library;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/semantics.dart';

import '../design/tokens.dart';
import '../design/motion.dart';

class EditorialArticleRoute extends PageRoute<void> {
  EditorialArticleRoute({
    required this.builder,
    this.reduceMotion = false,
    super.settings,
  }) : super(allowSnapshotting: false);

  final WidgetBuilder builder;
  final bool reduceMotion;

  bool get _reduced =>
      reduceMotion || SemanticsBinding.instance.disableAnimations;

  late final AnimationController _drag;
  bool _dragging = false;
  bool _popRequested = false;
  bool _disposed = false;
  double? _releaseVelocity;

  @override
  bool get opaque => false;
  @override
  bool get barrierDismissible => false;
  @override
  Color get barrierColor => ImageColors.shade.withValues(alpha: .30);
  @override
  String? get barrierLabel => null;
  @override
  bool get maintainState => true;
  @override
  Duration get transitionDuration =>
      _reduced ? AppMotion.reducedFade : AppMotion.heroDuration;
  @override
  Duration get reverseTransitionDuration =>
      _reduced ? AppMotion.reducedFade : AppMotion.heroDuration;

  @override
  AnimationController createAnimationController() {
    _drag = AnimationController.unbounded(
      vsync: navigator!,
      value: 0,
      debugLabel: 'editorial-direct-drag',
    );
    return super.createAnimationController();
  }

  @override
  Simulation? createSimulation({required bool forward}) {
    if (_reduced) return null;
    final c = controller!;
    return SpringSimulation(
      AppMotion.hero,
      c.value,
      forward ? 1 : 0,
      forward ? c.velocity : (_releaseVelocity ?? c.velocity),
      snapToEnd: true,
    )..tolerance = const Tolerance(distance: .001, velocity: .001);
  }

  /// 弹回中再次抓取时保留当前显示位置，不等待动画结束。
  bool beginDismiss() {
    final c = controller;
    if (_disposed ||
        _popRequested ||
        navigator == null ||
        c == null ||
        !isCurrent ||
        isFirst ||
        willHandlePopInternally ||
        popDisposition == RoutePopDisposition.doNotPop ||
        _dragging) {
      return false;
    }
    // An entering Hero must finish its handoff before a direct drag starts;
    // otherwise its overlay would continue moving independently of the page.
    if (!c.isCompleted) {
      c.stop();
      c.value = 1;
    }
    _drag.stop();
    _dragging = true;
    return true;
  }

  /// 累计增量。页面 translateY 直接使用此比例 × 屏高，不缩小手指位移。
  void updateDismiss(double deltaFraction) {
    if (!_dragging || _disposed || !deltaFraction.isFinite) return;
    _drag.value = (_drag.value + deltaFraction).clamp(0.0, 1.0);
  }

  void endDismiss(double velocityFraction) {
    if (!_dragging || _disposed) return;
    _dragging = false;
    if (_popRequested || !isActive) return;
    final velocity = velocityFraction.isFinite
        ? velocityFraction.clamp(-8.0, 8.0)
        : 0.0;
    final canPop =
        isCurrent &&
        !willHandlePopInternally &&
        popDisposition != RoutePopDisposition.doNotPop;
    final dismiss =
        canPop &&
        ((_drag.value > .18 && velocity > -.35) ||
            (_drag.value > .015 && velocity > .85));
    if (dismiss) {
      // Freeze the direct transform. The ordinary pop measures the Hero here,
      // at the position the user actually released, rather than its old origin.
      _releaseVelocity = -velocity;
      navigator!.pop();
    } else if (_reduced) {
      _drag.value = 0;
    } else {
      _drag.animateWith(
        SpringSimulation(
          AppMotion.hero,
          _drag.value,
          0,
          velocity,
          snapToEnd: true,
        )..tolerance = const Tolerance(distance: .0001, velocity: .0001),
      );
    }
  }

  @override
  bool didPop(void result) {
    _dragging = false;
    _drag.stop();
    _popRequested = true;
    final popped = super.didPop(result);
    if (!popped) _popRequested = false;
    return popped;
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    // Hero measures relative to the route subtree, not to the screen. Keep a
    // stationary render root and place the direct transform below it so that
    // the release rectangle includes the real dragged position and scale.
    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedBuilder(
            animation: _drag,
            child: RepaintBoundary(child: builder(context)),
            builder: (context, child) {
              final fraction = _drag.value.clamp(0.0, 1.0);
              final reduced =
                  _reduced || MediaQuery.disableAnimationsOf(context);
              return Transform.translate(
                offset: Offset(0, fraction * MediaQuery.sizeOf(context).height),
                child: Transform.scale(
                  scale: reduced ? 1 : 1 - fraction * .06,
                  alignment: Alignment.topCenter,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      reduced ? 0 : AppRadii.lg * fraction,
                    ),
                    child: child,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final reduced = _reduced || MediaQuery.disableAnimationsOf(context);
    // The shared cover flies in the Navigator overlay. The rest of the reader
    // must leave on the same clock, revealing the retained home underneath.
    // Scaling an opaque reader to .96 left its text on screen until disposal.
    // Keep this repaint boundary stable so fading does not repaint the article.
    return FadeTransition(
      opacity: animation,
      child: AnimatedBuilder(
        animation: animation,
        child: RepaintBoundary(child: child),
        builder: (context, child) => Transform.translate(
          offset: Offset(
            0,
            reduced ? 0 : (1 - animation.value.clamp(0.0, 1.0)) * 32,
          ),
          child: child,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _dragging = false;
    _drag.dispose();
    super.dispose();
  }
}
