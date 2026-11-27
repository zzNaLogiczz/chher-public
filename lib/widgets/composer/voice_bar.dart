import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../design/composer_tokens.dart';
import '../../design/motion.dart';
import '../../design/tokens.dart';
import '../../design/voice_tokens.dart';
import '../../di.dart';
import '../../ui/press.dart';
import '../expressive_controls.dart';
import 'dictation_controller.dart';
import 'voice_liquid_motion.dart';
import 'voice_liquid_painter.dart';

typedef _T = VoiceTokens;

class VoiceBar extends StatefulWidget {
  final DictationController controller;
  final bool enabled;

  const VoiceBar({super.key, required this.controller, this.enabled = true});

  @override
  State<VoiceBar> createState() => _VoiceBarState();
}

class _VoiceBarState extends State<VoiceBar>
    with SingleTickerProviderStateMixin {
  final _liquidOverlay = OverlayPortalController();
  final _barLink = LayerLink();
  int? _pointer;
  bool _stopTap = false;
  bool _showFocus = false;
  bool _hovered = false;
  final _liquid = VoiceLiquidMotion();
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  DictationFrame? _previousFrame;
  double? _idleWidth;
  double? _liquidWidth;

  DictationController get _controller => widget.controller;
  bool get _needsTick => _controller.listening || _liquid.needsTick;

  Duration _listeningElapsed() => _controller.listeningElapsed;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    _controller.attachPresentation();
    _controller.addListener(_onFrame);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _liquid.setReduced(MediaQuery.disableAnimationsOf(context));
    _updateLiquid(_controller.value);
  }

  @override
  void didUpdateWidget(VoiceBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != _controller) {
      oldWidget.controller.removeListener(_onFrame);
      oldWidget.controller.detachPresentation();
      _controller.attachPresentation();
      _controller.addListener(_onFrame);
      _onFrame();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onFrame);
    scheduleMicrotask(_controller.detachPresentation);
    _ticker.dispose();
    _liquid.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed) {
    final delta = elapsed - _lastTick;
    _lastTick = elapsed;
    _liquid.advance(delta.inMicroseconds / Duration.microsecondsPerSecond);
    _publishVisual();
    if (_liquid.retractionComplete) _controller.completeRetraction();
    if (_controller.value.holdBar && !_liquid.holdingForFly) {
      _controller.releaseCancelBar();
    }
    if (!_needsTick) {
      _ticker.stop();
      if (_controller.value.phase == DictationPhase.canceling) {
        _controller.completeCancel();
      }
      if (!_controller.barExpanded && _liquidWidth != null) {
        _liquidOverlay.hide();
        setState(() => _liquidWidth = null);
      }
    }
  }

  Offset _barTop(RenderBox box) =>
      Offset(box.size.width / 2, (box.size.height - _T.barHeight) / 2);

  void _publishVisual() {
    final render = context.findRenderObject();
    final blob = _liquid.goo.blob;
    final center = blob == null || render is! RenderBox || !render.hasSize
        ? null
        : render.localToGlobal(
            _barTop(render) + Offset(blob.center.x, blob.center.y),
          );
    _controller.visual.value = (
      volume: _liquid.frame.volume,
      dropCenter: center,
      flyElapsed: _liquid.flyElapsed,
      cancelElapsed: _liquid.cancelElapsed,
    );
  }

  void _updateLiquid(DictationFrame frame) {
    final render = context.findRenderObject();
    final box = render is RenderBox && render.hasSize ? render : null;
    final barTop = box == null ? null : _barTop(box);
    final finger = frame.pointer != null && box != null
        ? box.globalToLocal(frame.pointer!) - barTop!
        : null;
    final labelFloor = box == null
        ? null
        : VoiceGooTokens.labelScreenTop - box.localToGlobal(barTop!).dy;
    _liquid.update(
      phase: frame.phase,
      listening: _controller.listening,
      volume: frame.volume,
      finger: finger?.dx,
      fingerY: finger?.dy,
      pull: frame.pull,
      detached: frame.detached,
      width: _liquidWidth ?? box?.size.width ?? 0,
      labelFloor: labelFloor,
      retracting: frame.retracting,
      holdBar: frame.holdBar,
      flyCount: frame.holdBar ? frame.text.combined.characters.length : 0,
    );
    if (_controller.barExpanded &&
        !_liquidOverlay.isShowing &&
        Overlay.maybeOf(context) != null) {
      _liquidOverlay.show();
    }
    if (_needsTick && !_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    }
  }

  void _onFrame() {
    final frame = _controller.value;
    if (!_controller.active || (frame.pointer == null && !_stopTap)) {
      _pointer = null;
      _stopTap = false;
    }
    final previous = _previousFrame;
    if (previous != null &&
        _controller.listening &&
        frame.detached != previous.detached) {
      unawaited(
        frame.detached
            ? HapticFeedback.mediumImpact()
            : HapticFeedback.lightImpact(),
      );
    }
    if (MediaQuery.supportsAnnounceOf(context)) {
      if (_controller.listening &&
          frame.seconds == _T.warningSecond &&
          previous?.seconds != frame.seconds) {
        _announce(_T.countdownLabel(_T.warningSecond));
      }
      if (frame.phase == DictationPhase.review &&
          frame.phase != previous?.phase) {
        _announce('已插入 ${frame.text.combined.characters.length} 字');
      }
    }
    _previousFrame = frame;
    _updateLiquid(frame);
    _publishVisual();
    if (frame.phase != previous?.phase ||
        frame.seconds != previous?.seconds ||
        frame.detached != previous?.detached ||
        frame.holdBar != previous?.holdBar ||
        (frame.pull > _T.pullingHintDistance) !=
            ((previous?.pull ?? 0) > _T.pullingHintDistance)) {
      setState(() {});
    }
  }

  void _announce(String message) {
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        message,
        Directionality.of(context),
      ),
    );
  }

  void _down(PointerDownEvent event) {
    if (!widget.enabled ||
        _pointer != null ||
        event.buttons != kPrimaryButton) {
      return;
    }
    final locked = _controller.value.phase == DictationPhase.locked;
    if (_controller.active && !locked) return;
    _pointer = event.pointer;
    _stopTap = locked;
    if (!locked) {
      unawaited(HapticFeedback.lightImpact());
      _controller.start(pointer: event.position);
    }
  }

  void _up(PointerEvent event, {bool interrupted = false}) {
    if (_pointer != event.pointer) return;
    _pointer = null;
    if (_stopTap) {
      if (!interrupted) _controller.finish();
    } else {
      if (!interrupted) _controller.move(event.position);
      _controller.release(interrupted: interrupted);
    }
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (widget.enabled &&
        event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        (_controller.active || _controller.canUndo)) {
      _controller.cancel();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final frame = _controller.value;
    final listening = _controller.listening;
    final actionable = widget.enabled && (!_controller.active || listening);
    final exposeCountdown =
        listening &&
        frame.seconds >= _T.warningSecond &&
        !MediaQuery.supportsAnnounceOf(context);
    final label = switch (frame.phase) {
      _ when frame.detached => '已断开，松手撤销',
      DictationPhase.hold => '上滑取消',
      DictationPhase.locked => '轻点结束',
      _ => '语音输入',
    };
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _key,
      child: FocusableActionDetector(
        // Keep focus through finalization so Escape remains available.
        enabled: widget.enabled,
        mouseCursor: actionable
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onShowFocusHighlight: (show) => setState(() => _showFocus = show),
        onShowHoverHighlight: (show) => setState(() => _hovered = show),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter, includeRepeats: false):
              ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space, includeRepeats: false):
              ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              if (actionable) _controller.toggle();
              return null;
            },
          ),
        },
        child: Semantics(
          label: label,
          explicitChildNodes: exposeCountdown,
          button: true,
          enabled: actionable,
          onTap: actionable ? _controller.toggle : null,
          child: RawGestureDetector(
            gestures: {
              if (actionable)
                EagerGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                      EagerGestureRecognizer
                    >(EagerGestureRecognizer.new, (_) {}),
            },
            excludeFromSemantics: true,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _down,
              onPointerMove: (event) {
                if (_pointer == event.pointer && !_stopTap) {
                  _controller.move(event.position);
                }
              },
              onPointerUp: _up,
              onPointerCancel: (event) => _up(event, interrupted: true),
              child: ActionFocusRing(
                visible: _showFocus,
                child: Stack(
                  children: [
                    ExcludeSemantics(
                      child: _visual(frame, listening, actionable),
                    ),
                    if (exposeCountdown)
                      Positioned.fill(
                        child: Semantics(
                          container: true,
                          liveRegion: frame.seconds == _T.warningSecond,
                          label: _T.countdownLabel(frame.seconds),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _visual(DictationFrame frame, bool listening, bool actionable) =>
      LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final expanded = _controller.barExpanded;
          if (expanded) {
            if (_liquidWidth != width) {
              _liquidWidth = width;
              _liquid.resize(width);
            }
          } else {
            _idleWidth = width;
          }
          final liquidWidth = _liquidWidth;
          final capsuleWidth = math.min(
            liquidWidth ?? width,
            _idleWidth ?? ComposerTokens.capsuleWidth,
          );
          return OverlayPortal(
            controller: _liquidOverlay,
            overlayChildBuilder: (context) {
              if (liquidWidth == null || liquidWidth <= 0) {
                return const SizedBox.shrink();
              }
              return IgnorePointer(
                child: ExcludeSemantics(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: CompositedTransformFollower(
                      link: _barLink,
                      targetAnchor: Alignment.center,
                      followerAnchor: Alignment.center,
                      showWhenUnlinked: false,
                      child: SizedBox(
                        width: liquidWidth,
                        height: _T.barHeight,
                        child: _VoiceTrack(
                          frame: frame,
                          motion: _liquid,
                          capsuleWidth: capsuleWidth,
                          listening: listening,
                          listeningElapsed: _listeningElapsed,
                          showFocus: _showFocus,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
            child: CompositedTransformTarget(
              link: _barLink,
              child: SizedBox(
                width: width,
                height: expanded ? _T.barHeight : ComposerTokens.capsuleHeight,
                child: expanded
                    ? null
                    : VoiceCapsule(
                        hovered: actionable && _hovered,
                        enabled: actionable,
                      ),
              ),
            ),
          );
        },
      );
}

class _VoiceTrack extends StatefulWidget {
  const _VoiceTrack({
    required this.frame,
    required this.motion,
    required this.capsuleWidth,
    required this.listening,
    required this.listeningElapsed,
    required this.showFocus,
  });

  final DictationFrame frame;
  final VoiceLiquidMotion motion;
  final double capsuleWidth;
  final bool listening;
  final ValueGetter<Duration> listeningElapsed;
  final bool showFocus;

  @override
  State<_VoiceTrack> createState() => _VoiceTrackState();
}

class _VoiceTrackState extends State<_VoiceTrack> {
  VoiceLiquidPaints? _paints;
  AppTokens? _tokens;
  double? _width;
  TextStyle? _baseTextStyle;
  TextScaler? _scaler;
  TextDirection? _direction;
  double? _pixelRatio;

  @override
  void dispose() {
    _paints?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final tokens = AppTokens.of(context);
      final baseTextStyle = DefaultTextStyle.of(context).style;
      final scaler = MediaQuery.textScalerOf(context);
      final direction = Directionality.of(context);
      final pixelRatio = MediaQuery.devicePixelRatioOf(context);
      if (_paints == null ||
          _tokens != tokens ||
          _width != width ||
          _baseTextStyle != baseTextStyle ||
          _scaler != scaler ||
          _direction != direction ||
          _pixelRatio != pixelRatio) {
        _paints?.dispose();
        _paints = VoiceLiquidPaints(
          tokens,
          width,
          baseTextStyle: baseTextStyle,
          textScaler: scaler,
          textDirection: direction,
          pixelRatio: pixelRatio,
        );
        _baseTextStyle = baseTextStyle;
        _scaler = scaler;
        _direction = direction;
        _pixelRatio = pixelRatio;
        _tokens = tokens;
        _width = width;
      }
      final frame = widget.frame;
      final seconds = math.min(frame.seconds, _T.secondsPerMinute - 1);
      final warning = seconds >= _T.warningSecond;
      final time = warning
          ? _T.countdownLabel(seconds)
          : '0:${seconds.toString().padLeft(2, '0')}';
      final holding = frame.phase == DictationPhase.hold;
      final hint = switch (frame.phase) {
        DictationPhase.hold =>
          !frame.detached && frame.pull > _T.pullingHintDistance
              ? '继续上滑'
              : '上滑取消',
        DictationPhase.locked => '轻点结束',
        _ => '',
      };
      final label = ComposerTokens.voiceLabel.copyWith(
        color: ComposerTokens.voiceOnGradient,
        fontWeight: _T.hintWeight,
        shadows: _T.labelShadows,
      );
      final timeStyle = label.copyWith(
        color: warning
            ? ComposerTokens.voiceTimeWarning
            : ComposerTokens.voiceOnGradient,
        fontWeight: _T.timeWeight,
        fontFeatures: _T.timeFeatures,
      );
      final hintIconWidth = holding ? _T.hintIcon + _T.hintGap : 0.0;
      const inset = ComposerTokens.voiceLabelInset;
      final labelWidth = math.max(0.0, width / 2 - inset);

      double measure(String text, TextStyle style, double maxWidth) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: baseTextStyle.merge(style)),
          textDirection: direction,
          textScaler: scaler,
          locale: Localizations.maybeLocaleOf(context),
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: maxWidth);
        final measured = painter.width;
        painter.dispose();
        return measured;
      }

      final left =
          inset + measure(time, timeStyle, labelWidth) + _T.lineLabelGap;
      final right =
          width -
          inset -
          (hint.isEmpty
              ? 0
              : measure(
                      hint,
                      label,
                      math.max(0.0, labelWidth - hintIconWidth),
                    ) +
                    hintIconWidth +
                    _T.lineLabelGap);
      final showIcon =
          holding && !frame.detached && labelWidth >= hintIconWidth;
      final timeText = Text(
        time,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: timeStyle,
      );
      final headroom = MediaQuery.sizeOf(context).height;
      final sideRoom = math.max(
        _T.maxOverhang / 2,
        (MediaQuery.sizeOf(context).width - width) / 2,
      );
      return IgnorePointer(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: -sideRoom,
              right: -sideRoom,
              top: -headroom,
              bottom: -_T.paintHeadroom,
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: VoiceLiquidPainter(
                    motion: widget.motion,
                    paints: _paints!,
                    fullWidth: width,
                    headroom: headroom,
                    sideRoom: sideRoom,
                    capsuleWidth:
                        widget.capsuleWidth *
                        (widget.listening && !widget.motion.frame.reduced
                            ? _T.capsuleSquash
                            : 1),
                    lineLeft: left,
                    lineRight: right,
                    listeningElapsed: widget.listeningElapsed,
                  ),
                ),
              ),
            ),
            if (widget.showFocus && widget.listening)
              const Positioned.fill(
                child: ActionFocusRing(visible: true, child: SizedBox.expand()),
              ),
            if (widget.listening || frame.holdBar)
              Positioned.fill(
                left: inset,
                right: inset,
                child: AnimatedBuilder(
                  animation: widget.motion,
                  builder: (_, child) => Opacity(
                    opacity: widget.motion.frame.labels,
                    child: child,
                  ),
                  child: Row(
                    textDirection: TextDirection.ltr,
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child:
                              warning &&
                                  widget.listening &&
                                  !MediaQuery.disableAnimationsOf(context)
                              ? TweenAnimationBuilder<double>(
                                  key: ValueKey(seconds),
                                  tween: Tween(begin: 1.2, end: 1),
                                  duration: _T.countdownPop,
                                  curve: _T.countdownCurve,
                                  builder: (_, scale, child) => Transform.scale(
                                    scale: scale,
                                    child: child,
                                  ),
                                  child: timeText,
                                )
                              : timeText,
                        ),
                      ),
                      Expanded(
                        child: Row(
                          textDirection: TextDirection.ltr,
                          mainAxisAlignment: MainAxisAlignment.end,
                          spacing: showIcon ? _T.hintGap : 0,
                          children: [
                            if (showIcon)
                              const Icon(
                                AppIcons.voicePull,
                                color: ComposerTokens.voiceOnGradient,
                                size: _T.hintIcon,
                              ),
                            if (hint.isNotEmpty && !frame.detached)
                              Flexible(
                                child: Text(
                                  hint,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: label,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class VoiceStatus extends StatelessWidget {
  final DictationController controller;
  final bool chat;
  final bool enabled;

  const VoiceStatus({
    super.key,
    required this.controller,
    this.chat = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final phase = controller.value.phase;
      final review = phase == DictationPhase.review;
      final interrupted =
          phase == DictationPhase.errorNetwork ||
          phase == DictationPhase.errorUnavailable;
      final permission = phase == DictationPhase.errorPermission;
      final message = switch (phase) {
        DictationPhase.finalizing => '识别中',
        DictationPhase.errorPermission => '麦克风权限未开启',
        DictationPhase.errorNetwork =>
          controller.canUndo ? '网络中断，已保留识别的文字' : '网络不可用',
        DictationPhase.errorUnavailable => '语音识别暂不可用',
        DictationPhase.errorSilent => '没有听到声音，再试一次',
        DictationPhase.errorBusy => '用的人有点多，稍后再试',
        _ => null,
      };
      if (!review && message == null) return const SizedBox.shrink();
      final t = AppTokens.of(context);
      final count = controller.value.text.combined.characters.length;
      return TweenAnimationBuilder<double>(
        key: ValueKey(phase),
        tween: Tween(begin: 0, end: 1),
        duration: MediaQuery.disableAnimationsOf(context)
            ? AppMotion.reducedFade
            : AppMotion.fade,
        curve: AppMotion.contentFadeCurve,
        builder: (_, value, child) => Opacity(opacity: value, child: child),
        child: Padding(
          padding: EdgeInsets.only(
            left: ComposerTokens.stripInset,
            right: ComposerTokens.stripInset,
            bottom: chat
                ? ComposerTokens.voiceChatChipGap
                : ComposerTokens.voiceChipGap,
          ),
          child: Center(
            child: Semantics(
              container: review,
              explicitChildNodes: review,
              liveRegion: review && !MediaQuery.supportsAnnounceOf(context),
              label: review && !MediaQuery.supportsAnnounceOf(context)
                  ? '已插入 $count 字'
                  : null,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(
                    ComposerTokens.voiceRadius,
                  ),
                  border: Border.all(
                    color: t.fill2,
                    width: ComposerTokens.voiceOutline,
                  ),
                  boxShadow: t.shadowE1,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: ComposerTokens.voiceChipHeight,
                  ),
                  child: Padding(
                    padding: ComposerTokens.voiceChipPadding,
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (message != null)
                          Semantics(
                            liveRegion: true,
                            child: Padding(
                              padding: ComposerTokens.voiceMessagePadding,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                spacing: ComposerTokens.voiceChipGap,
                                children: [
                                  if (permission || interrupted)
                                    Icon(
                                      AppIcons.warning,
                                      color: t.warn,
                                      size: ComposerTokens.voiceIcon,
                                    ),
                                  Flexible(
                                    child: Text(
                                      message,
                                      style: ComposerTokens.voiceLabel.copyWith(
                                        color: t.text2,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (review && controller.value.hitLimit)
                          Padding(
                            padding: ComposerTokens.voiceMessagePadding,
                            child: Text(
                              '已到 60 秒',
                              style: ComposerTokens.voiceLabel.copyWith(
                                color: t.text2,
                              ),
                            ),
                          ),
                        if (review || (interrupted && controller.canUndo))
                          _action(
                            t,
                            '撤销',
                            controller.cancel,
                            icon: AppIcons.undo,
                          ),
                        if (review)
                          _action(
                            t,
                            '重说',
                            controller.retry,
                            icon: AppIcons.refresh,
                          ),
                        if (permission)
                          _action(t, '去设置', openVoiceSettings, accent: true),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _action(
    AppTokens t,
    String label,
    VoidCallback action, {
    IconData? icon,
    bool accent = false,
  }) => PressHighlight(
    onTap: enabled ? action : null,
    color: t.fill,
    borderRadius: BorderRadius.circular(ComposerTokens.capsuleRadius),
    child: ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: ComposerTokens.capsuleHeight,
      ),
      child: Padding(
        padding: ComposerTokens.voiceActionPadding,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: t.text2, size: ComposerTokens.voiceIcon),
              const SizedBox(width: ComposerTokens.voiceChipGap),
            ],
            Flexible(
              child: Text(
                label,
                style: ComposerTokens.voiceLabel.copyWith(
                  color: accent ? t.accent : t.text,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class VoiceCapsule extends StatelessWidget {
  const VoiceCapsule({super.key, this.hovered = false, this.enabled = true});

  final bool hovered;
  final bool enabled;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) =>
        _buildCapsule(context, constraints.maxWidth),
  );

  Widget _buildCapsule(BuildContext context, double width) {
    final t = AppTokens.of(context);
    final barColors = [t.ai1, t.ai1, t.ai3, t.ai2, t.ai2];
    final barCount = ComposerTokens.barHeights.length;
    final waveWidth =
        barCount * ComposerTokens.barWidth +
        (barCount - 1) * ComposerTokens.barGap;
    final gap = width.clamp(0.0, ComposerTokens.capsuleGap);
    return Semantics(
      label: '语音输入',
      excludeSemantics: true,
      child: Container(
        width: width,
        height: ComposerTokens.capsuleHeight,
        decoration: BoxDecoration(
          color: hovered ? t.fill2 : t.fill,
          borderRadius: BorderRadius.circular(ComposerTokens.capsuleRadius),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: gap,
          children: [
            SizedBox(
              width: waveWidth.clamp(0.0, width - gap),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: ComposerTokens.barGap,
                  children: [
                    for (final (index, height)
                        in ComposerTokens.barHeights.indexed)
                      Container(
                        width: ComposerTokens.barWidth,
                        height: height,
                        decoration: BoxDecoration(
                          color: barColors[index],
                          borderRadius: BorderRadius.circular(
                            ComposerTokens.barRadius,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Flexible(
              child: Text(
                '按住说话',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ComposerTokens.voiceLabel.copyWith(
                  color: enabled ? t.text2 : t.text3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
