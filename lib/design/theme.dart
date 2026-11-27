/// ThemeData 构建:把设计令牌接到 Material 组件上
///
/// TextTheme 槽位只映射 typography.dart 的字号角色,防止组件偷偷引入新字号。
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kReleaseMode;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart'
    show GestureBinding, PointerDeviceKind, VelocityTracker;
import 'package:flutter/scheduler.dart' show SchedulerBinding, Ticker;
import 'package:flutter/cupertino.dart'
    show
        CupertinoPageTransition,
        CupertinoFullscreenDialogTransition,
        CupertinoThemeData,
        CupertinoTextThemeData;

import 'tokens.dart';
import 'motion.dart';
import 'sheet_tokens.dart';
import 'package:flutter/services.dart';
import 'system_ui.dart';
import 'typography.dart';
import '../widgets/expressive_controls.dart';
import '../core/app_log.dart';

/// 风格 × 明暗 → 令牌组。壳与组件经 AppTokens.of 读到的 style 即由此注入。
AppTokens tokensFor(Brightness brightness, AppearanceStyle style) =>
    switch ((style, brightness)) {
      (AppearanceStyle.misty, Brightness.light) => AppTokens.mistyLight,
      (AppearanceStyle.misty, Brightness.dark) => AppTokens.mistyDark,
      (_, Brightness.light) => AppTokens.cinnabarLight,
      (_, Brightness.dark) => AppTokens.cinnabarDark,
    };

/// [style] 缺省朱砂红:旧调用点(测试与审阅工具)不指定风格时保持 1.0.8 观感。
ThemeData buildAppTheme(
  Brightness brightness, [
  AppearanceStyle style = AppearanceStyle.cinnabar,
]) {
  final t = tokensFor(brightness, style);

  // 中文走系统字:iOS 为 PingFang SC,Android 为思源 / Noto Sans CJK SC。
  // 不打包任何 CJK 字体(单字重十几 MB)。
  final textTheme = _buildTextTheme(t);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    cupertinoOverrideTheme: CupertinoThemeData(
      primaryColor: t.accent,
      scaffoldBackgroundColor: t.bg,
      barBackgroundColor: t.surface,
      textTheme: CupertinoTextThemeData(
        primaryColor: t.accent,
        textStyle: TextStyle(fontSize: AppType.sizeBody, color: t.text),
        navActionTextStyle: TextStyle(
          fontSize: AppType.sizeBody,
          color: t.accent,
        ),
        tabLabelTextStyle: TextStyle(
          fontSize: AppType.sizeFootnote,
          color: t.text2,
        ),
      ),
    ),
    actionIconTheme: ActionIconThemeData(
      backButtonIconBuilder: (_) => const Icon(AppIcons.back, size: 22),
      closeButtonIconBuilder: (_) => const Icon(AppIcons.close, size: 22),
    ),
    scaffoldBackgroundColor: t.bg,
    canvasColor: t.bg,
    dividerColor: Colors.transparent,
    extensions: [t],
    colorScheme: _colorScheme(t, brightness),
    textTheme: textTheme,
    dividerTheme: const DividerThemeData(
      color: Colors.transparent,
      thickness: 0,
      space: 8,
    ),
    appBarTheme: _appBarTheme(t, textTheme),
    cardTheme: _cardTheme(t),
    dialogTheme: DialogThemeData(
      backgroundColor: brightness == Brightness.dark
          ? Radix.slate2Dark
          : Radix.whiteA12,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: AppType.headline.copyWith(color: t.text),
      contentTextStyle: AppType.callout.copyWith(color: t.text2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
    ),
    listTileTheme: ListTileThemeData(
      textColor: t.text,
      iconColor: t.text3,
      minVerticalPadding: 0,
    ),
    inputDecorationTheme: _inputTheme(t),
    textButtonTheme: _textButtonTheme(t),
    outlinedButtonTheme: _outlinedButtonTheme(t),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: t.accent,
      linearMinHeight: 2,
    ),
    // 编辑器选区:朱砂红用朱 200/光标朱 700,薄雾白用 accent 的透明罩
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: t.accent,
      selectionColor: t.style == AppearanceStyle.misty
          ? (t.isDark ? const Color(0x6670B8FF) : const Color(0x660D74CE))
          : (t.isDark ? const Color(0x5A5A2A27) : const Color(0xFFFFD4CC)),
      selectionHandleColor: t.accent,
    ),
    snackBarTheme: _snackBarTheme(t),
    bottomSheetTheme: _bottomSheetTheme(t),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.accentFill,
        foregroundColor: t.accent,
        minimumSize: const Size(44, 46),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        textStyle: const TextStyle(
          fontSize: AppType.sizeBody,
          fontWeight: FontWeight.w600,
        ),
        shape: const StadiumBorder(),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.all(10),
        foregroundColor: t.text2,
        iconSize: 22,
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: _ReadingPageTransitions(),
        TargetPlatform.iOS: _ReadingPageTransitions(),
        TargetPlatform.macOS: _ReadingPageTransitions(),
      },
    ),
    splashFactory: NoSplash.splashFactory,
    highlightColor: t.fill.withValues(alpha: .65),
    hoverColor: t.fill.withValues(alpha: .45),
  );
}

ColorScheme _colorScheme(AppTokens t, Brightness brightness) {
  return ColorScheme(
    brightness: brightness,
    primary: t.accent,
    onPrimary: t.onAccent,
    primaryContainer: t.accentFill,
    onPrimaryContainer: t.accent,
    secondary: t.text2,
    onSecondary: t.surface,
    secondaryContainer: t.fill,
    onSecondaryContainer: t.text,
    tertiary: t.accent,
    onTertiary: t.surface,
    tertiaryContainer: t.accentFill,
    onTertiaryContainer: t.accent,
    error: t.red,
    onError: t.onAccent,
    surface: t.bg,
    onSurface: t.text,
    onSurfaceVariant: t.text2,
    surfaceContainerLowest: t.surface,
    surfaceContainerLow: t.bg,
    surfaceContainer: t.fill,
    surfaceContainerHigh: t.fill2,
    surfaceContainerHighest: t.separator,
    outline: t.separator,
    outlineVariant: t.separator,
    shadow: Radix.slate12Light,
    scrim: t.scrim,
    inverseSurface: t.text,
    onInverseSurface: t.bg,
    inversePrimary: t.accentFill,
    surfaceTint: t.accent,
  );
}

AppBarTheme _appBarTheme(AppTokens t, TextTheme textTheme) {
  return AppBarTheme(
    systemOverlayStyle: AppSystemUi.forBrightness(
      t.isDark ? Brightness.dark : Brightness.light,
    ),
    backgroundColor: t.bg,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: false,
    toolbarHeight: 58,
    iconTheme: IconThemeData(color: t.text2, size: 21),
    actionsIconTheme: IconThemeData(color: t.text2, size: 20),
    titleTextStyle: textTheme.titleLarge,
    titleSpacing: 8,
  );
}

/// Standard cards use surface contrast; editorial elevation is applied locally.
CardThemeData _cardTheme(AppTokens t) {
  return CardThemeData(
    color: t.surface,
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.md),
      side: BorderSide.none,
    ),
  );
}

InputDecorationTheme _inputTheme(AppTokens t) {
  final radius = BorderRadius.circular(AppRadii.sm);
  return InputDecorationTheme(
    filled: true,
    fillColor: t.fill,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    hintStyle: TextStyle(fontSize: AppType.sizeFootnote, color: t.text3),
    border: OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: t.accent, width: AppSpace.focusWidth),
    ),
  );
}

TextButtonThemeData _textButtonTheme(AppTokens t) {
  return TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: t.accent,
      textStyle: const TextStyle(
        fontSize: AppType.sizeFootnote,
        fontWeight: FontWeight.w500,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      minimumSize: const Size(44, 44),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
    ),
  );
}

OutlinedButtonThemeData _outlinedButtonTheme(AppTokens t) {
  return OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: t.accent,
      side: BorderSide.none,
      textStyle: const TextStyle(
        fontSize: AppType.sizeFootnote,
        fontWeight: FontWeight.w600,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      minimumSize: const Size(44, 44),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
    ),
  );
}

SnackBarThemeData _snackBarTheme(AppTokens t) {
  return SnackBarThemeData(
    backgroundColor: t.text,
    contentTextStyle: TextStyle(fontSize: AppType.sizeFootnote, color: t.bg),
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.sm),
    ),
  );
}

BottomSheetThemeData _bottomSheetTheme(AppTokens t) {
  return BottomSheetThemeData(
    backgroundColor: t.surface,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(AppSheetTokens.radius)),
    ),
  );
}

/// 字号角色映射:display/headline -> largeTitle,title -> title2/headline,
/// body -> body/callout/footnote,label -> subhead/footnote/caption
TextTheme _buildTextTheme(AppTokens t) {
  TextStyle c(TextStyle s, [Color? color, FontWeight? w]) =>
      s.copyWith(color: color ?? t.text, fontWeight: w);

  return TextTheme(
    displayLarge: c(AppType.largeTitle),
    displayMedium: c(AppType.largeTitle),
    displaySmall: c(AppType.largeTitle),
    headlineLarge: c(AppType.largeTitle),
    headlineMedium: c(AppType.largeTitle),
    headlineSmall: c(AppType.largeTitle),
    titleLarge: c(AppType.title2),
    titleMedium: c(AppType.headline),
    titleSmall: c(AppType.footnote, null, FontWeight.w600),
    bodyLarge: c(AppType.body),
    bodyMedium: c(AppType.callout),
    bodySmall: c(AppType.footnote, t.text2),
    labelLarge: c(AppType.subhead, null, FontWeight.w600),
    labelMedium: c(AppType.footnote, t.text2, FontWeight.w500),
    labelSmall: c(AppType.caption, t.text3),
  );
}

class _ReadingPageTransitions extends PageTransitionsBuilder {
  const _ReadingPageTransitions();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final transition = reduced
        ? AnimatedBuilder(
            animation: animation,
            child: child,
            builder: (context, child) => Stack(
              fit: StackFit.expand,
              children: [
                child!,
                if (animation.value < 1)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ColoredBox(
                        color: Theme.of(context).scaffoldBackgroundColor
                            .withValues(alpha: 1 - animation.value),
                      ),
                    ),
                  ),
              ],
            ),
          )
        : route.fullscreenDialog
        ? CupertinoFullscreenDialogTransition(
            primaryRouteAnimation: animation,
            secondaryRouteAnimation: secondaryAnimation,
            linearTransition: true,
            child: child,
          )
        : CupertinoPageTransition(
            primaryRouteAnimation: animation,
            secondaryRouteAnimation: secondaryAnimation,
            linearTransition: true,
            child: child,
          );
    return _ReadingBackGesture(route: route, child: transition);
  }
}

/// Both Android predictive back and the in-app edge drag drive the same route.
class _ReadingBackGesture extends StatefulWidget {
  const _ReadingBackGesture({required this.route, required this.child});
  final PageRoute<dynamic> route;
  final Widget child;

  @override
  State<_ReadingBackGesture> createState() => _ReadingBackGestureState();
}

enum _BackGestureSource { edge, system }

class _ReadingBackGestureState extends State<_ReadingBackGesture>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _clock = GestureBinding.instance.samplingClock.stopwatch();
  bool _tracking = false;
  _BackGestureSource? _gestureSource;
  double _systemFirstValue = 1;
  bool _pendingSystemGesture = false;
  int _systemUpdates = 0;
  bool _settling = false;
  bool _invoking = false;
  int _generation = 0;
  VelocityTracker? _velocityTracker;
  late final Ticker _gestureFrames = createTicker(_onGestureFrame);
  Duration _lastProgressFrame = Duration.zero;
  static const _gestureFrameIdle = Duration(milliseconds: 80);

  double get _releaseVelocity =>
      (_velocityTracker?.getVelocity().pixelsPerSecond.dx ?? 0).clamp(-4, 4);

  void _wakeGestureFrames() {
    if (_gestureSource != _BackGestureSource.system ||
        MediaQuery.disableAnimationsOf(context) ||
        (WidgetsBinding.instance.lifecycleState != null &&
            WidgetsBinding.instance.lifecycleState !=
                AppLifecycleState.resumed)) {
      return;
    }
    _lastProgressFrame = SchedulerBinding.instance.currentSystemFrameTimeStamp;
    if (!_gestureFrames.isActive) _gestureFrames.start();
  }

  void _onGestureFrame(Duration _) {
    // Platform progress arrives around vsync. Keep the next frame booked while
    // it is moving, so pending requests cannot merge every second update.
    // Progress itself stays direct; no interpolation or page rebuild here.
    if (!_tracking ||
        _gestureSource != _BackGestureSource.system ||
        !widget.route.isCurrent ||
        SchedulerBinding.instance.currentSystemFrameTimeStamp -
                _lastProgressFrame >=
            _gestureFrameIdle) {
      _gestureFrames.stop();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _gestureFrames.stop();
  }

  double _systemStartValue = 1;
  double _systemStartProgress = 0;
  NavigatorState? _gestureNavigator;
  bool _driving = false;
  bool _initialMotion = true;
  double _routeVelocity = 0;

  void _rememberVelocity() => _routeVelocity = _controller.velocity;

  void _routeStatus(AnimationStatus status) {
    if (_driving ||
        _tracking ||
        _settling ||
        widget.route.popGestureInProgress ||
        (status != AnimationStatus.forward &&
            status != AnimationStatus.reverse)) {
      return;
    }
    _driving = true;
    final forward = status == AnimationStatus.forward;
    if (MediaQuery.disableAnimationsOf(context)) {
      if (forward) {
        _controller.animateTo(1, duration: AppMotion.reducedFade);
      } else {
        _controller.animateBack(0, duration: AppMotion.reducedFade);
      }
    } else {
      AppMotion.settle(
        _controller,
        target: forward ? 1 : 0,
        motion: AppMotion.reveal,
        velocity: _routeVelocity,
        tolerance: forward
            ? AppMotion.routeEntryTolerance
            : Tolerance.defaultTolerance,
      );
    }
    _driving = false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _gestureFrames.stop();
    if (_initialMotion) {
      _initialMotion = false;
      _routeStatus(_controller.status);
    }
  }

  // The SDK exposes gesture updates but no velocity-aware release method.
  // ignore: invalid_use_of_protected_member
  AnimationController get _controller => widget.route.controller!;
  bool get _enabled =>
      widget.route.isCurrent &&
      (widget.route.popGestureEnabled ||
          ((_settling || _tracking) &&
              !widget.route.willHandlePopInternally &&
              widget.route.popDisposition == RoutePopDisposition.pop));

  @override
  void initState() {
    super.initState();
    _gestureFrames;
    WidgetsBinding.instance.addObserver(this);
    _controller.addStatusListener(_routeStatus);
    _controller.addListener(_rememberVelocity);
  }

  void _stopGesture() {
    _gestureNavigator?.didStopUserGesture();
    _gestureNavigator = null;
  }

  bool _start(double progress, _BackGestureSource source) {
    if (!_enabled) return false;
    _generation++;
    _stopGesture();
    _tracking = true;
    _gestureSource = source;
    _settling = false;
    _velocityTracker = VelocityTracker.withKind(PointerDeviceKind.touch)
      ..addPosition(Duration.zero, Offset(progress, 0));
    _clock
      ..reset()
      ..start();
    widget.route.handleStartBackGesture(progress: progress);
    _gestureNavigator = widget.route.navigator;
    _wakeGestureFrames();
    return true;
  }

  void _update(double progress) {
    if (!_tracking) return;
    _velocityTracker?.addPosition(_clock.elapsed, Offset(progress, 0));
    if (progress == _controller.value) return;
    _wakeGestureFrames();
    widget.route.handleUpdateBackGestureProgress(progress: progress);
  }

  void _finish({required bool pop, double? velocity}) {
    if (!_tracking) return;
    final releaseVelocity = velocity ?? _releaseVelocity;
    _gestureFrames.stop();
    _tracking = false;
    _gestureSource = null;
    _settling = true;
    _clock.stop();
    final generation = _generation;
    final route = widget.route;
    final navigator = route.navigator;
    final value = _controller.value;
    final shouldPop =
        pop &&
        route.isCurrent &&
        !route.willHandlePopInternally &&
        route.popDisposition == RoutePopDisposition.pop;
    if (shouldPop) {
      navigator?.pop();
      // Navigator starts its default reverse; resume from the actual release.
      _controller.value = value;
    }
    AppMotion.settle(
      _controller,
      target: shouldPop || !route.isActive ? 0 : 1,
      motion: AppMotion.reveal,
      velocity: releaseVelocity,
      reduced: MediaQuery.disableAnimationsOf(context),
    ).whenCompleteOrCancel(() {
      if (generation != _generation) return;
      _settling = false;
      _stopGesture();
    });
    if (pop && !shouldPop && route.isCurrent) {
      // A draft/close lock may have changed since start. Let maybePop notify
      // PopScope, including its confirmation UI, while the page springs back.
      unawaited(navigator?.maybePop());
    }
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent event) {
    _pendingSystemGesture = false;
    _systemUpdates = 0;
    _systemFirstValue = _controller.value;
    if (MediaQuery.disableAnimationsOf(context) ||
        Theme.of(context).platform != TargetPlatform.android) {
      return _recordSystemStart(false, 'reduced-or-platform');
    }
    if (event.isButtonEvent) {
      // Zero/missing coordinates are only a button heuristic. Rejecting start
      // makes WidgetsBinding discard every later progress event, even if the
      // stream turns out to be a drag. Claim the stream without moving; a
      // progress update starts the gesture, a commit alone remains maybePop.
      _pendingSystemGesture = _enabled;
      _systemStartValue = _settling || _tracking ? _controller.value : 1;
      _systemStartProgress = event.progress;
      if (_pendingSystemGesture) _gestureSource = _BackGestureSource.system;
      return _recordSystemStart(_pendingSystemGesture, 'pending-touch');
    }
    // Android restarts progress at zero even when it interrupts our return spring.
    final value = _settling || _tracking
        ? _controller.value
        : 1 - event.progress;
    if (!_start(value, _BackGestureSource.system)) {
      return _recordSystemStart(false, 'route-not-ready');
    }
    _systemStartValue = value;
    _systemStartProgress = event.progress;
    return _recordSystemStart(true, 'drag');
  }

  bool _recordSystemStart(bool accepted, String reason) {
    if (widget.route.isCurrent) {
      _systemLog(
        'start accepted=$accepted reason=$reason '
        'status=${_controller.status.name}',
      );
    }
    return accepted;
  }

  // Temporary device diagnostic: AppLog intentionally suppresses logcat in
  // release. Keep this to start/end only; no content, coordinates or frame logs.
  void _systemLog(String phase) {
    final message =
        'ChherBackDart $phase observer=_ReadingBackGestureState '
        'route=${widget.route.settings.name ?? "unnamed"} '
        'updates=$_systemUpdates tracking=$_tracking '
        'animation=${_systemFirstValue.toStringAsFixed(4)}'
        '->${_controller.value.toStringAsFixed(4)} '
        'velocity=${(_tracking ? _releaseVelocity : 0).toStringAsFixed(3)}';
    AppLog.i('back', message);
    if (kReleaseMode) {
      // ignore: avoid_print
      print(message);
    }
  }

  void _recordSystemEnd(String phase) {
    if (!_tracking && !_pendingSystemGesture && _systemUpdates == 0) {
      _systemFirstValue = _controller.value;
    }
    _systemLog(phase);
    // WidgetsBinding may retain this observer for a later commit-only event.
    _systemUpdates = 0;
    _systemFirstValue = _controller.value;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent event) {
    _systemUpdates++;
    if (_pendingSystemGesture) {
      if (event.progress <= _systemStartProgress) return;
      _pendingSystemGesture = false;
      if (!_start(_systemStartValue, _BackGestureSource.system)) return;
    }
    _update(
      (_systemStartValue - (event.progress - _systemStartProgress)).clamp(
        0.0,
        1.0,
      ),
    );
  }

  @override
  void handleCommitBackGesture() {
    _recordSystemEnd('commit');
    _pendingSystemGesture = false;
    if (_tracking) {
      _finish(pop: true);
    } else {
      _gestureSource = null;
      unawaited(_invokeBack());
    }
  }

  Future<void> _invokeBack() async {
    // The binding can retain this observer after cancellation. Android may
    // subsequently send only commit (no start/progress), so it must still take
    // the ordinary back path. maybePop targets any panel now above this route
    // and preserves PopScope/LocalHistoryEntry handling.
    if (_invoking || !widget.route.isActive) return;
    final navigator = widget.route.navigator;
    if (navigator == null) return;
    _invoking = true;
    final wasSettling = _settling;
    final generation = _generation;
    if (wasSettling) {
      // Release the navigation gesture so an ordinary pop can start its spring,
      // but keep the cancellation spring alive if a panel or draft consumes back.
      _settling = false;
      _stopGesture();
    }
    try {
      if (!await navigator.maybePop()) await SystemNavigator.pop();
    } finally {
      _invoking = false;
      if (mounted &&
          wasSettling &&
          generation == _generation &&
          widget.route.isActive &&
          _controller.isAnimating) {
        _settling = true;
      }
    }
  }

  @override
  void handleCancelBackGesture() {
    _recordSystemEnd('cancel');
    _pendingSystemGesture = false;
    _finish(pop: false);
    _gestureSource = null;
  }

  @override
  void dispose() {
    _generation++;
    _clock.stop();
    _gestureFrames.dispose();
    _stopGesture();
    _controller.removeStatusListener(_routeStatus);
    _controller.removeListener(_rememberVelocity);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context) ||
        widget.route.fullscreenDialog) {
      return widget.child;
    }
    final rtl = Directionality.of(context) == TextDirection.rtl;
    double logical(double value) => rtl ? -value : value;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        PositionedDirectional(
          start: 0,
          top: 0,
          bottom: 0,
          width: 20 + MediaQuery.paddingOf(context).left,
          child: IgnorePointer(
            ignoring: !_enabled,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              // Android cancels this pointer stream when predictive back takes
              // ownership. Even a recognizer that never started a drag can emit
              // onCancel; an accepted one can emit onEnd. Neither may finish or
              // move the system-owned route.
              onHorizontalDragStart: (_) {
                if (_gestureSource != null) return;
                _start(_controller.value, _BackGestureSource.edge);
              },
              onHorizontalDragUpdate: (details) {
                if (_gestureSource != _BackGestureSource.edge) return;
                _update(
                  (_controller.value -
                          logical(details.delta.dx) / context.size!.width)
                      .clamp(0.0, 1.0),
                );
              },
              onHorizontalDragEnd: (details) {
                if (_gestureSource != _BackGestureSource.edge) return;
                final velocity =
                    logical(details.velocity.pixelsPerSecond.dx) /
                    context.size!.width;
                _finish(
                  pop: velocity.abs() >= 1
                      ? velocity > 0
                      : _controller.value < .5,
                  velocity: -velocity,
                );
              },
              onHorizontalDragCancel: () {
                if (_gestureSource != _BackGestureSource.edge) return;
                _finish(pop: false, velocity: 0);
              },
            ),
          ),
        ),
      ],
    );
  }
}
