import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:smooth_sheets/smooth_sheets.dart';

import '../design/motion.dart';
import '../design/sheet_tokens.dart';

/// Keeps smooth_sheets' scroll handoff, with one shared release spring.
class AppSheetRoute<T> extends ModalSheetRoute<T> {
  AppSheetRoute({
    required super.builder,
    required super.barrierColor,
    super.barrierLabel = '关闭',
    this.reduced = false,
    this.fadeWhenReduced = false,
    this.holdViewInsetsOnExit = false,
    this.docked = false,
  }) : super(
         swipeDismissible: false,
         transitionCurve: Curves.linear,
         transitionDuration: !reduced
             ? AppMotion.sheetDuration
             : fadeWhenReduced
             ? AppMotion.reducedFade
             : Duration.zero,
       );

  final bool reduced;
  final bool fadeWhenReduced;
  final bool holdViewInsetsOnExit;
  final bool docked;
  MediaQueryData? _lastViewportMedia;
  double? _dragStart;
  bool _closingSheet = false;
  bool _dragCancelled = false;
  bool _finishQueued = false;
  BuildContext? _sheetContext;
  SheetController? _sheetController;

  @override
  Simulation? createSimulation({required bool forward}) => reduced
      ? null
      : SpringSimulation(
          AppMotion.sheet.description,
          controller!.value,
          forward ? 1 : 0,
          controller!.velocity,
          snapToEnd: true,
        );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => reduced && fadeWhenReduced
      ? FadeTransition(opacity: animation, child: child)
      : super.buildTransitions(context, animation, secondaryAnimation, child);

  @override
  Widget buildViewport(BuildContext context, Widget child) {
    Widget viewport(BuildContext context) {
      final inset = docked ? 0.0 : AppSheetTokens.inset;
      return SheetViewport(
        padding: EdgeInsets.fromLTRB(
          inset,
          MediaQuery.viewPaddingOf(context).top + AppSheetTokens.inset,
          inset,
          docked ? MediaQuery.viewInsetsOf(context).bottom : inset,
        ),
        child: child,
      );
    }

    if (!holdViewInsetsOnExit) return viewport(context);
    return Builder(
      builder: (context) {
        final media = MediaQuery.of(context);
        if (isActive) _lastViewportMedia = media;
        final previous = _lastViewportMedia ?? media;
        // Keep the outgoing sheet at the height from which it started its
        // exit, while the IME runs its own hide animation.
        return MediaQuery(
          data: media.copyWith(
            viewInsets: previous.viewInsets,
            padding: previous.padding,
          ),
          child: RepaintBoundary(child: Builder(builder: viewport)),
        );
      },
    );
  }

  @override
  Widget buildSheet(BuildContext context) {
    _sheetContext = context;
    return NotificationListener<SheetNotification>(
      onNotification: (event) {
        if (event is SheetDragStartNotification) {
          _dragStart = event.metrics.offset;
          _closingSheet = false;
          _dragCancelled = false;
        }
        if (event is SheetDragCancelNotification) _dragCancelled = true;
        if (_closingSheet && event.metrics.offset <= .5) _finishDismissal();
        return false;
      },
      child: DefaultSheetController(
        child: Builder(
          builder: (context) {
            _sheetController = DefaultSheetController.of(context);
            return Listener(
              onPointerCancel: (_) => _dragCancelled = true,
              child: super.buildSheet(context),
            );
          },
        ),
      ),
    );
  }

  void _finishDismissal() {
    if (_finishQueued) return;
    _finishQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _finishQueued = false;
      if (!_closingSheet || !isCurrent) return;
      _closingSheet = false;
      if (popDisposition == RoutePopDisposition.pop) {
        navigator!.pop();
        controller!.value = 0;
      } else {
        _dragCancelled = true;
        onPopInvokedWithResult(false, null);
        final sheet = _sheetController;
        final metrics = sheet?.metrics;
        if (sheet != null && metrics != null) {
          sheet.animateTo(
            // A same-position move resumes AppSheetPhysics' ballistic snap.
            SheetOffset.absolute(metrics.offset),
            duration: AppMotion.immediateSheet,
            curve: Curves.linear,
          );
        }
      }
    });
  }

  bool _dismiss(double velocity, SheetMetrics metrics) {
    final start = _dragStart ?? metrics.minOffset;
    final dragged = start - metrics.offset;
    final height = math.min(start, metrics.size.height);
    final requested =
        velocity < -AppSheetTokens.dismissVelocity ||
        (height > 0 && dragged > height * AppSheetTokens.dismissFraction);
    final context = _sheetContext;
    if (_dragCancelled ||
        !requested ||
        !isCurrent ||
        (context != null && MediaQuery.viewInsetsOf(context).bottom > 0)) {
      return false;
    }
    if (popDisposition != RoutePopDisposition.pop) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (isCurrent) onPopInvokedWithResult(false, null);
      });
      return false;
    }
    return _closingSheet = true;
  }

  @override
  Widget buildModalBarrier() => CustomPaint(
    painter: _SheetBarrierPainter(
      reduced && fadeWhenReduced ? animation! : sheetVisibility,
      barrierColor!,
    ),
    child: ModalBarrier(
      dismissible: barrierDismissible,
      semanticsLabel: barrierLabel,
      onDismiss: () => navigator?.maybePop(),
    ),
  );
}

class AppSheetPhysics extends ClampingSheetPhysics {
  AppSheetPhysics._(this.route, this.reduced)
    : super(spring: AppMotion.sheet.description);

  factory AppSheetPhysics.of(
    BuildContext context, {
    SheetController? controller,
  }) {
    final route = ModalRoute.of(context);
    if (route is AppSheetRoute && controller != null) {
      route._sheetController = controller;
    }
    return AppSheetPhysics._(
      route is AppSheetRoute ? route : null,
      MediaQuery.disableAnimationsOf(context),
    );
  }

  final AppSheetRoute<dynamic>? route;
  final bool reduced;

  @override
  double computeOverflow(double delta, SheetMetrics metrics) => route == null
      ? super.computeOverflow(delta, metrics)
      : math.max(0, metrics.offset + delta - metrics.maxOffset);

  @override
  double applyPhysicsToOffset(double delta, SheetMetrics metrics) =>
      route == null
      ? super.applyPhysicsToOffset(delta, metrics)
      : (metrics.offset + delta).clamp(0.0, metrics.maxOffset) - metrics.offset;

  @override
  Simulation? createBallisticSimulation(
    double velocity,
    SheetMetrics metrics,
    SheetSnapGrid snapGrid,
  ) {
    final dismiss = route?._dismiss(velocity, metrics) ?? false;
    final target = dismiss
        ? 0.0
        : snapGrid
              .getSnapOffset(metrics, metrics.offset, velocity)
              .resolve(metrics);
    if ((target - metrics.offset).abs() < .01) {
      if (dismiss) route!._finishDismissal();
      return null;
    }
    if (reduced) return _ImmediateSheetSimulation(target);
    return ScrollSpringSimulation(spring, metrics.offset, target, velocity);
  }
}

class _ImmediateSheetSimulation extends Simulation {
  _ImmediateSheetSimulation(this.target);
  final double target;
  @override
  double x(double time) => target;
  @override
  double dx(double time) => 0;
  @override
  bool isDone(double time) => true;
}

class _SheetBarrierPainter extends CustomPainter {
  _SheetBarrierPainter(this.visibility, this.color)
    : super(repaint: visibility);
  final Animation<double> visibility;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) => canvas.drawRect(
    Offset.zero & size,
    Paint()..color = color.withValues(alpha: color.a * visibility.value),
  );
  @override
  bool shouldRepaint(_SheetBarrierPainter oldDelegate) =>
      oldDelegate.visibility != visibility || oldDelegate.color != color;
}
