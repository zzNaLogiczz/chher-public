import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Badge;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../design/motion.dart';
import '../design/support_tokens.dart';
import '../widgets/expressive_controls.dart';
import 'badge_world.dart';
import 'support_actions.dart';
import 'support_badge_painter.dart';
import 'support_badge_sprites.dart';
import 'support_motion.dart';

/// The screen-sized canvas owns the world, sprites, and foreground subscription.
class SupportBadgeStage extends StatefulWidget {
  const SupportBadgeStage({
    super.key,
    required this.viewport,
    required this.restingCard,
    required this.topWall,
    required this.onSave,
  });

  static const semanticsLabel = '收款码挂牌，正面支付宝，背面微信，点按翻面，长按保存';

  final Size viewport;
  final Rect restingCard;
  final double topWall;
  final ValueChanged<SupportCode> onSave;

  @override
  SupportBadgeStageState createState() => SupportBadgeStageState();
}

class SupportBadgeStageState extends State<SupportBadgeStage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _badgeId = 'support-pass';
  static const _anchorY = -40.0;
  static const _gestureSlop = 8.0;

  final _repaint = ValueNotifier(0);
  final _hapticClock = Stopwatch()..start();
  late final Ticker _ticker = createTicker(_tick);
  late BadgeWorld _world;
  late SupportBadgeVisuals _visuals;
  late final _painter = SupportBadgePainter(
    visuals: _visuals,
    repaint: _repaint,
  );
  StreamSubscription<MotionSample>? _subscription;
  MotionSample _sample = restingMotion;
  MotionVector? _sleepGravity;
  Duration? _lastFrame;
  Duration? _lastImpact;
  ({Size size, double dpr, bool dark})? _assetRequest;
  var _assetGeneration = 0;
  var _initialized = false;
  var _placed = false;
  var _visible = false;
  var _foreground = false;
  var _reduced = false;
  var _focused = false;
  var _flipMicros = 0;
  var _flashMicros = 0;
  var _flashKinds = const <SupportCode>{};
  _BadgePress? _press;
  Timer? _hold;

  bool get _active => _visible && _foreground;
  BadgeCard get _card => _visuals.badge.card;
  SupportBadgeProjection get _projection => SupportBadgeProjection(
    _card,
    perspectiveOrigin: Offset(
      widget.viewport.width / 2,
      widget.viewport.height * .34,
    ),
  );

  @override
  void initState() {
    super.initState();
    final binding = WidgetsBinding.instance;
    _foreground = binding.lifecycleState == AppLifecycleState.resumed;
    binding.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (!_initialized) {
      _reduced = reduced;
      _world = BadgeWorld();
      _visuals = SupportBadgeVisuals(
        _addBadge(),
        dark: dark,
        reducedMotion: reduced,
      );
      _initialized = true;
    } else if (_reduced != reduced) {
      final faceYaw = _projection.frontFacing ? 0.0 : math.pi;
      _cancelPress();
      _clearEffects();
      _reduced = reduced;
      _visuals.reducedMotion = reduced;
      if (reduced) {
        _card.yawTarget = faceYaw;
        _card.lift = 0;
        _world.placeAtRest(_visuals.badge);
        _placed = true;
      }
    }
    _visuals.dark = dark;
    _visible =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.isCurrentOf(context) ?? true);
    _setWalls();
    _loadSprites();
    _syncActivity();
    _repaint.value++;
  }

  @override
  void didUpdateWidget(covariant SupportBadgeStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.restingCard != oldWidget.restingCard) {
      _cancelPress();
      final yawTarget = _card.yawTarget;
      _world = BadgeWorld();
      _visuals.badge = _addBadge();
      _card.yawTarget = yawTarget;
      _world.placeAtRest(_visuals.badge);
      _loadSprites();
    }
    _setWalls();
    _syncActivity();
    if (!_reduced &&
        (widget.restingCard != oldWidget.restingCard ||
            widget.viewport != oldWidget.viewport ||
            widget.topWall != oldWidget.topWall)) {
      _wake();
    }
    _repaint.value++;
  }

  Badge _addBadge() {
    final rect = widget.restingCard;
    final slot = rect.width * 13 / 150;
    return _world.addBadge(
      _badgeId,
      rect.center.dx,
      _anchorY,
      rect.top + slot - _anchorY,
      rect.width,
      rect.height,
      slot,
    );
  }

  void _setWalls() {
    _world.setWalls(
      6,
      widget.viewport.width - 6,
      widget.topWall,
      widget.viewport.height - 6,
    );
  }

  void _loadSprites() {
    final request = (
      size: widget.restingCard.size,
      dpr: MediaQuery.devicePixelRatioOf(context).clamp(1.0, 2.0),
      dark: _visuals.dark,
    );
    if (request == _assetRequest) return;
    final previous = _assetRequest;
    _assetRequest = request;
    if (previous?.size != request.size) {
      _visuals.sprites?.dispose();
      _visuals.sprites = null;
    }
    final generation = ++_assetGeneration;
    unawaited(_generateSprites(request, generation));
  }

  Future<void> _generateSprites(
    ({Size size, double dpr, bool dark}) request,
    int generation,
  ) async {
    try {
      final sprites = await SupportBadgeSprites.load(
        width: request.size.width,
        height: request.size.height,
        slot: request.size.width * 13 / 150,
        devicePixelRatio: request.dpr,
        dark: request.dark,
      );
      if (!mounted || generation != _assetGeneration) {
        sprites.dispose();
        return;
      }
      _visuals.sprites?.dispose();
      _visuals.sprites = sprites;
      _syncActivity();
      _repaint.value++;
    } catch (error, stack) {
      if (!mounted || generation != _assetGeneration) return;
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'support badge sprites',
        ),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncActivity();
  }

  void _syncActivity() {
    if (!_active || _reduced) {
      final subscription = _subscription;
      _subscription = null;
      if (subscription != null) unawaited(subscription.cancel());
    }
    if (!_active || _visuals.sprites == null) {
      _cancelPress();
      _sleep();
      return;
    }
    if (!_placed) {
      _placed = true;
      if (!_reduced) {
        final badge = _visuals.badge;
        final dropRatio =
            (-10 - (_card.h - _card.slot) - _anchorY) / badge.strap.length;
        _world.placeForDrop(badge, 18, dropRatio, 0, 27);
      }
    }
    if (_reduced) {
      if (_flashKinds.isEmpty && _visuals.fade == 1) {
        _sleep();
      } else {
        _wake();
      }
      return;
    }
    if (_subscription == null) {
      _sample = restingMotion;
      _subscription = SupportMotion.listen(_onMotion, onError: (_, _) {});
      _wake();
    } else if (_sleepGravity == null) {
      _wake();
    }
  }

  void _onMotion(MotionSample sample) {
    if (!_active || _reduced) return;
    _sample = sample;
    final reference = _sleepGravity;
    if (reference != null && shouldWakeBadge(sample, reference)) _wake();
  }

  void _wake() {
    if (!_active || _visuals.sprites == null || _ticker.isActive) return;
    if (!_reduced) _world.calmFor = 0;
    _lastFrame = null;
    _sleepGravity = null;
    _ticker.start();
  }

  void _sleep() {
    _ticker.stop();
    _lastFrame = null;
    _sleepGravity = _sample.gravity;
  }

  void _tick(Duration elapsed) {
    final previous = _lastFrame ?? elapsed;
    _lastFrame = elapsed;
    final micros = (elapsed - previous).inMicroseconds;
    if (!_reduced) {
      final input = badgeInput(_sample);
      _world.setGravity(input.gx, input.gy, input.gz, input.shakeZ);
      _world.setRotationRates(input.rotation.yaw, input.rotation.pitch);
      _visuals.lightHalfVector = input.lightHalfVector;
      _world.step(micros / Duration.microsecondsPerSecond);
      _impactFeedback();
    } else if (_visuals.fade < 1) {
      _flipMicros += micros;
      final progress = (_flipMicros / AppMotion.reducedFade.inMicroseconds)
          .clamp(0.0, 1.0);
      _visuals.fade = Curves.easeOut.transform(progress);
    }
    if (_flashKinds.isNotEmpty) {
      _flashMicros += micros;
      final duration = _reduced ? AppMotion.reducedFade : SupportTokens.flash;
      final progress = _flashMicros / duration.inMicroseconds;
      if (progress >= 1) _flashKinds = const {};
      _visuals.frontFlash = _flashKinds.contains(SupportCode.alipay)
          ? progress
          : -1;
      _visuals.backFlash = _flashKinds.contains(SupportCode.weChat)
          ? progress
          : -1;
    }
    _repaint.value++;
    if (_flashKinds.isEmpty &&
        (_reduced
            ? _visuals.fade == 1
            : _world.calmFor > 2 && !_world.isGrabbing)) {
      _sleep();
    }
  }

  void _impactFeedback() {
    final events = _world.takeEvents();
    final now = _hapticClock.elapsed;
    final last = _lastImpact;
    if (last != null && now - last < SupportTokens.impactInterval) return;
    for (final event in events) {
      final threshold = event.kind == BadgeEventKind.strap ? 600 : 900;
      if (event.speed > threshold) {
        _lastImpact = now;
        unawaited(HapticFeedback.lightImpact());
        break;
      }
    }
  }

  void animateAction({required double tug, Set<SupportCode> flash = const {}}) {
    if (flash.isNotEmpty) {
      _flashKinds = flash;
      _flashMicros = 0;
      _visuals.frontFlash = flash.contains(SupportCode.alipay) ? 0 : -1;
      _visuals.backFlash = flash.contains(SupportCode.weChat) ? 0 : -1;
    }
    if (!_reduced && tug != 0) _world.tug(_badgeId, tug);
    if (!_reduced || flash.isNotEmpty) _wake();
  }

  void _clearEffects() {
    _flashKinds = const {};
    _visuals
      ..frontFlash = -1
      ..backFlash = -1
      ..fade = 1
      ..lightHalfVector = lightHalfVector(restingMotion.gravity);
  }

  void _flip([double direction = 1]) {
    if (!_active || _visuals.sprites == null) return;
    if (_reduced) {
      _card.yawTarget = _card.yawTarget == 0 ? math.pi : 0;
      _card.yaw = _card.yawTarget;
      _flipMicros = 0;
      _visuals.fade = 0;
      _repaint.value++;
    } else {
      _world.flip(_badgeId, direction);
    }
    unawaited(HapticFeedback.selectionClick());
    _wake();
  }

  void _saveVisible() {
    if (!_active || _visuals.sprites == null) return;
    _world.endGrab();
    unawaited(HapticFeedback.mediumImpact());
    widget.onSave(
      _projection.frontFacing ? SupportCode.alipay : SupportCode.weChat,
    );
  }

  void _down(PointerDownEvent event) {
    if (!_active ||
        _visuals.sprites == null ||
        _press != null ||
        event.buttons != kPrimaryButton) {
      return;
    }
    final point = event.localPosition;
    final cardPoint = _projection.hitLocal(point);
    if (cardPoint == null) return;
    final press = _BadgePress(
      event.pointer,
      point,
      event.timeStamp,
      cardPoint.dx >= 0 ? 1 : -1,
    );
    _press = press;
    _hold = Timer(AppMotion.longPress, () {
      if (_press != press || !_active) return;
      press.saved = true;
      _saveVisible();
    });
    if (!_reduced) {
      _world.startGrab(_badgeId, point.dx, point.dy);
      _wake();
    }
  }

  void _move(PointerMoveEvent event) {
    final press = _press;
    if (press == null || press.pointer != event.pointer || press.saved) return;
    final point = event.localPosition;
    if (!press.moved && (point - press.origin).distance >= _gestureSlop) {
      press.moved = true;
      _hold?.cancel();
    }
    if (!_reduced) _world.moveGrab(point.dx, point.dy);
  }

  void _up(PointerUpEvent event) {
    final press = _press;
    if (press == null || press.pointer != event.pointer) return;
    _cancelPress();
    if (!press.moved &&
        !press.saved &&
        (event.localPosition - press.origin).distance < _gestureSlop &&
        event.timeStamp - press.started < SupportTokens.tapLimit) {
      _flip(press.direction);
    }
  }

  void _cancelPress() {
    _hold?.cancel();
    _hold = null;
    _press = null;
    _world.endGrab();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hold?.cancel();
    final subscription = _subscription;
    if (subscription != null) unawaited(subscription.cancel());
    _ticker.dispose();
    _repaint.dispose();
    _visuals.sprites?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _up,
        onPointerCancel: (event) {
          if (event.pointer == _press?.pointer) _cancelPress();
        },
        child: RepaintBoundary(child: CustomPaint(painter: _painter)),
      ),
      Positioned.fromRect(
        rect: widget.restingCard,
        child: Semantics(
          container: true,
          button: true,
          label: SupportBadgeStage.semanticsLabel,
          onTap: _flip,
          onLongPress: _saveVisible,
          child: IgnorePointer(
            child: FocusableActionDetector(
              onShowFocusHighlight: (focused) {
                if (mounted) setState(() => _focused = focused);
              },
              shortcuts: const {
                SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
                SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
              },
              actions: {
                ActivateIntent: CallbackAction<ActivateIntent>(
                  onInvoke: (_) {
                    _flip();
                    return null;
                  },
                ),
              },
              child: ActionFocusRing(
                visible: _focused,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

class _BadgePress {
  _BadgePress(this.pointer, this.origin, this.started, this.direction);

  final int pointer;
  final Offset origin;
  final Duration started;
  final double direction;
  bool moved = false;
  bool saved = false;
}
