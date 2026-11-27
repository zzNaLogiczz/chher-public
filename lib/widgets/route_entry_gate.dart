import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Holds a cold result until the first frame after the route has entered.
class RouteEntryGate {
  ModalRoute<dynamic>? _route;
  Completer<bool>? _pending;
  int? _frame;
  bool _entered = false;

  void update(ModalRoute<dynamic>? route) {
    if (identical(_route, route)) return;
    _route?.animation?.removeStatusListener(_statusChanged);
    _finish(false);
    _route = route;
    _entered =
        route?.offstage == false &&
        route?.animation?.status == AnimationStatus.completed;
    route?.animation?.addStatusListener(_statusChanged);
  }

  /// Null means the result can be committed immediately.
  Future<bool>? get wait {
    final route = _route;
    final animation = route?.animation;
    if (_entered || route == null || animation == null) return null;
    if (!route.offstage && animation.status == AnimationStatus.dismissed) {
      return Future.value(false);
    }
    return (_pending ??= Completer<bool>()).future;
  }

  void _statusChanged(AnimationStatus status) {
    // Hero measurements temporarily set the entering route's proxy to 1.0.
    if (_route?.offstage == true) return;
    if (status == AnimationStatus.completed) {
      if (_entered || _frame != null) return;
      _frame = SchedulerBinding.instance.scheduleFrameCallback((_) {
        _frame = null;
        final route = _route;
        if (route == null || !route.isActive) {
          _finish(false);
          return;
        }
        if (route.offstage || route.animation?.isCompleted != true) return;
        _entered = true;
        _finish(true);
      });
    } else if (status == AnimationStatus.dismissed) {
      _finish(false);
    }
  }

  void _finish(bool entered) {
    if (_frame case final frame?) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(frame);
      _frame = null;
    }
    _pending?.complete(entered);
    _pending = null;
  }

  void dispose() => update(null);
}
