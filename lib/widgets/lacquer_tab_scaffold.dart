import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:motor/motor.dart';

import '../design/motion.dart';
import '../design/system_ui.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../ui/nav_bar.dart';
import '../ui/feedback.dart';
import 'chhers_loader.dart';

/// The three scroll ranges are independent; there is no time animation while
/// the finger or scroll activity owns the position.
abstract final class CompactBarProgress {
  static double largeTitle(double p) => 1 - (p / .45).clamp(0.0, 1.0);
  static double background(double p) => ((p - .3) / .4).clamp(0.0, 1.0);
  static double smallTitle(double p) => ((p - .6) / .4).clamp(0.0, 1.0);
}

/// A tab host emits only for a second tap on its already selected destination.
class TabReselectScope extends InheritedWidget {
  const TabReselectScope({
    super.key,
    required this.requests,
    required super.child,
  });
  final ValueNotifier<int> requests;
  static ValueNotifier<int>? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TabReselectScope>()?.requests;
  @override
  bool updateShouldNotify(TabReselectScope oldWidget) =>
      requests != oldWidget.requests;
}

typedef TabScrollBuilder =
    Widget Function(
      ScrollController controller,
      List<Widget> slivers, {
      required bool active,
      double? mistyContentGap,
    });

/// The mast and seam paint behind the lazy content. A pager can share the mast
/// while each section keeps its own scroll view.
class LacquerTabScaffold extends StatefulWidget {
  const LacquerTabScaffold({
    super.key,
    required this.title,
    required this.slivers,
    this.eyebrow,
    this.header,
    this.actions = const [],
    this.controller,
    this.scrollOffset,
    this.onRefresh,
    this.seamOverlap = TabChromeTokens.seamOverlap,
    this.contentOnPaper = false,
    this.surface = AppSurface.grouped,
    this.discussionAnchor,
    this.compactAccessory,
    this.compactLeading,
    this.compactTitle,
    this.mistyCompact = false,
    this.headerBody,
    this.fadeHeaderBody = false,
    this.mistyContentGap = TabChromeTokens.mistyContentGap,
    this.scrollBody,
    this.mastOffsetForScroll,
  });
  final String title;

  /// Only the directory, messages and account tabs use the compact misty mast.
  final bool mistyCompact;
  final double mistyContentGap;

  /// Additional mast content below the common title.
  final Widget? headerBody;
  final bool fadeHeaderBody;
  final String? eyebrow;
  final Widget? header;
  final List<Widget> actions;
  final List<Widget> slivers;
  final ScrollController? controller;
  final ValueNotifier<double>? scrollOffset;
  final Widget Function(TabScrollBuilder, double collapseExtent)? scrollBody;
  final double Function(double)? mastOffsetForScroll;
  final Future<void> Function()? onRefresh;
  final double seamOverlap;

  /// Lists start below the seam; feature and account cards can cross it.
  final bool contentOnPaper;
  final AppSurface surface;
  final GlobalKey? discussionAnchor;
  final Widget? compactAccessory;
  final Widget? compactLeading;
  final Widget? compactTitle;
  @override
  State<LacquerTabScaffold> createState() => _LacquerTabScaffoldState();
}

class _LacquerTabScaffoldState extends State<LacquerTabScaffold>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final ScrollController _ownedScroll = ScrollController();
  late final ValueNotifier<double> _ownedOffset = ValueNotifier(0);
  ScrollController get _scroll => widget.controller ?? _ownedScroll;
  ValueNotifier<double> get _offset => widget.scrollOffset ?? _ownedOffset;
  final _headerKey = GlobalKey();
  final _discussion = ValueNotifier(false);
  late final _pull = AnimationController.unbounded(vsync: this);
  late final _refreshFade = AnimationController(
    vsync: this,
    duration: AppMotion.loadingOut,
    value: 1,
    animationBehavior: AnimationBehavior.preserve,
  );
  ValueNotifier<int>? _reselect;
  double _headerHeight = 160;
  double _discussionAt = double.infinity;
  double _rawPull = 0;
  bool _armed = false;
  bool _hapticSent = false;
  bool _refreshing = false;
  bool _refreshFading = false;
  bool _tickerEnabled = true;
  bool _pointerDown = false;
  int? _pointerId;
  Offset? _pointerStart;
  Offset? _lastPointer;
  VelocityTracker? _velocity;
  double get _barBottom =>
      MediaQuery.paddingOf(context).top + NavOverlay.barHeight;
  bool get _mistyCompact =>
      widget.mistyCompact &&
      AppTokens.of(context).style == AppearanceStyle.misty;
  double get _collapseAt => math.max(
    1,
    _headerHeight + (_mistyCompact ? 0 : widget.seamOverlap) - _barBottom,
  );
  bool get _reduced => MediaQuery.disableAnimationsOf(context);
  bool get _refreshVisible =>
      _tickerEnabled &&
      switch (WidgetsBinding.instance.lifecycleState) {
        null || AppLifecycleState.resumed => true,
        _ => false,
      };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final requests = TabReselectScope.of(context);
    if (_reselect != requests) {
      _reselect?.removeListener(_scrollToTop);
      _reselect = requests;
      _reselect?.addListener(_scrollToTop);
    }
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _settleHiddenRefresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _settleHiddenRefresh();

  void _settleHiddenRefresh() {
    if (_refreshVisible) return;
    _pointerId = null;
    _pointerDown = false;
    _rawPull = 0;
    _armed = false;
    if (_refreshFading) _refreshFade.value = 0;
    _pull.value = _refreshing && !_refreshFading
        ? TabChromeTokens.refreshHold
        : 0;
  }

  @override
  void didUpdateWidget(LacquerTabScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      (oldWidget.controller ?? _ownedScroll).removeListener(_onScroll);
      _scroll.addListener(_onScroll);
    }
  }

  void _scrollToTop() {
    if (_scroll.hasClients) {
      unawaited(AppMotion.scrollTo(_scroll.position, 0, reduced: _reduced));
    }
  }

  bool _discussionMeasurePending = false;
  void _onScroll() {
    _offset.value =
        widget.mastOffsetForScroll?.call(_scroll.offset) ?? _scroll.offset;
    _discussion.value = _offset.value >= _discussionAt;
    if (_discussionMeasurePending || widget.discussionAnchor == null) return;
    _discussionMeasurePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _discussionMeasurePending = false;
      if (mounted) _measureDiscussion();
    });
  }

  void _measureDiscussion() {
    final object = widget.discussionAnchor?.currentContext?.findRenderObject();
    final host = context.findRenderObject();
    if (object is RenderBox &&
        object.hasSize &&
        host is RenderBox &&
        _scroll.hasClients) {
      _discussionAt =
          object.localToGlobal(Offset.zero, ancestor: host).dy +
          _scroll.offset -
          _barBottom;
      _discussion.value = _offset.value >= _discussionAt;
    }
  }

  void _measure() {
    if (!mounted) return;
    final size = _headerKey.currentContext?.size;
    if (size != null && size.height != _headerHeight) {
      setState(() => _headerHeight = size.height);
    }
    _measureDiscussion();
  }

  void _down(PointerDownEvent e) {
    if (_pointerId != null) return;
    _pointerId = e.pointer;
    _pointerDown = true;
    _pointerStart = _lastPointer = e.position;
    _velocity = VelocityTracker.withKind(e.kind)
      ..addPosition(e.timeStamp, e.position);
    _pull.stop();
    // Invert the resistance function to continue a grabbed return spring.
    _rawPull = _pull.value <= 0
        ? 0
        : _pull.value *
              TabChromeTokens.pullResistance /
              math.max(1, TabChromeTokens.maxPull - _pull.value);
    _hapticSent = false;
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointerId) return;
    _velocity?.addPosition(e.timeStamp, e.position);
    final last = _lastPointer;
    _lastPointer = e.position;
    if (last == null || !_scroll.hasClients || widget.onRefresh == null) return;
    final total = e.position - _pointerStart!;
    if (total.dy.abs() < kTouchSlop || total.dy.abs() < total.dx.abs()) return;
    final dy = e.position.dy - last.dy;
    if (_rawPull > 0 || (_scroll.position.pixels <= 0 && dy > 0)) {
      _rawPull = math.max(0, _rawPull + dy);
      _pull.value =
          TabChromeTokens.maxPull *
          _rawPull /
          (TabChromeTokens.pullResistance + _rawPull);
      final armed = _pull.value >= TabChromeTokens.refreshHold;
      if (armed && !_hapticSent && !_refreshing) {
        _hapticSent = true;
        unawaited(HapticFeedback.selectionClick());
      }
      if (armed != _armed) setState(() => _armed = armed);
    }
  }

  void _release(int pointer, {bool cancelled = false}) {
    if (pointer != _pointerId) return;
    _pointerId = null;
    _pointerDown = false;
    final velocity = cancelled || _rawPull == 0
        ? 0.0
        : (_velocity?.getVelocity().pixelsPerSecond.dy ?? 0);
    final resistance =
        TabChromeTokens.maxPull *
        TabChromeTokens.pullResistance /
        math.pow(TabChromeTokens.pullResistance + _rawPull, 2);
    _rawPull = 0;
    if (_armed && !cancelled && !_refreshing && widget.onRefresh != null) {
      unawaited(_refresh(velocity * resistance));
    } else {
      if (_armed) setState(() => _armed = false);
      _settlePull(
        _refreshing ? TabChromeTokens.refreshHold : 0,
        velocity * resistance,
      );
    }
  }

  void _settlePull(double target, double velocity) {
    if (_pull.value == target && velocity == 0) return;
    if (_reduced || !_refreshVisible) {
      _pull.value = target;
      return;
    }
    _pull.animateWith(
      SpringSimulation(
        AppMotion.hero,
        _pull.value,
        target,
        velocity,
        snapToEnd: true,
      ),
    );
  }

  Future<void> _refresh(double velocity) async {
    setState(() => _refreshing = true);
    _settlePull(TabChromeTokens.refreshHold, velocity);
    _refreshFade.value = 1;
    try {
      await widget.onRefresh!();
    } catch (_) {
      if (mounted) AppToast.show(context, '刷新失败，请重试');
    } finally {
      if (mounted && _refreshVisible) {
        setState(() => _refreshFading = true);
        try {
          await _refreshFade.reverse().orCancel;
        } on TickerCanceled {
          // The page can leave during the fade.
        }
      }
      if (mounted) {
        setState(() {
          _refreshFading = false;
          _refreshing = false;
          _armed = false;
        });
        if (!_pointerDown) _settlePull(0, _pull.velocity);
      }
    }
  }

  Widget _wordmark(AppTokens t, {required bool misty}) {
    final normal = misty ? t.text3 : t.onLac;
    return AnimatedBuilder(
      animation: _pull,
      child: _refreshing
          ? FadeTransition(
              opacity: _refreshFade,
              child: ChhersLoader(
                size: ChhersLoaderSize.refresh,
                color: normal,
                delayed: false,
                animate: !_refreshFading,
              ),
            )
          : null,
      builder: (_, loading) => SizedBox(
        height: math.max(0.0, _pull.value),
        child: ClipRect(
          child: OverflowBox(
            minWidth: 0,
            minHeight: 0,
            maxHeight: double.infinity,
            child:
                loading ??
                (_pointerDown && _pull.value > 0
                    ? ChhersLoader.progress(
                        progress: (_pull.value / TabChromeTokens.refreshHold)
                            .clamp(0.0, 1.0),
                        color: misty && _armed ? t.accent : normal,
                      )
                    : null),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reselect?.removeListener(_scrollToTop);
    _scroll.removeListener(_onScroll);
    _ownedScroll.dispose();
    _ownedOffset.dispose();
    _discussion.dispose();
    _pull.dispose();
    _refreshFade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final misty = t.style == AppearanceStyle.misty;
    final compact = _mistyCompact;
    final headerBottom = compact
        ? 0.0
        : widget.header == null && widget.headerBody == null
        ? TabChromeTokens.editorialBottom
        : TabChromeTokens.headerBottom;
    final top = MediaQuery.paddingOf(context).top;
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    final title =
        widget.header ??
        TabHeader(
          title: widget.title,
          eyebrow: widget.eyebrow,
          actionCount: widget.actions.length,
        );
    final headerContent = Padding(
      padding: EdgeInsets.only(
        top:
            top +
            (widget.header == null
                ? 0
                : compact
                ? TabChromeTokens.mistyTop
                : TabChromeTokens.headerTop),
      ),
      child: ValueListenableBuilder<double>(
        valueListenable: _offset,
        child: widget.fadeHeaderBody
            ? Column(children: [title, ?widget.headerBody])
            : title,
        builder: (_, offset, child) => Opacity(
          key: const ValueKey('tab-large-title'),
          opacity: CompactBarProgress.largeTitle(offset / _collapseAt),
          child: child,
        ),
      ),
    );
    final header = Stack(
      key: widget.scrollBody == null
          ? _headerKey
          : const ValueKey('tab-shared-header'),
      clipBehavior: Clip.none,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            headerContent,
            if (!widget.fadeHeaderBody) ?widget.headerBody,
            SizedBox(height: headerBottom),
          ],
        ),
      ],
    );
    return Scaffold(
      backgroundColor: t.background(widget.surface),
      body: LayoutBuilder(
        builder: (context, constraints) {
          Widget scrollView(
            ScrollController controller,
            List<Widget> slivers, {
            required bool active,
            double? mistyContentGap,
          }) => CustomScrollView(
            controller: controller,
            physics: _PullPhysics(
              holding: () => active && _rawPull > 0,
              parent: const AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: widget.scrollBody == null
                    ? header
                    : SizedBox(height: _headerHeight),
              ),
              if (compact)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: mistyContentGap ?? widget.mistyContentGap,
                  ),
                )
              else if (widget.contentOnPaper)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: widget.seamOverlap + TabChromeTokens.paperTopInset,
                  ),
                ),
              ...slivers,
              SliverLayoutBuilder(
                builder: (_, c) => SliverToBoxAdapter(
                  child: SizedBox(
                    height: math.max(
                      0,
                      constraints.maxHeight +
                          _collapseAt -
                          c.precedingScrollExtent,
                    ),
                  ),
                ),
              ),
            ],
          );
          final shared = widget.scrollBody != null;
          final scrolling = Listener(
            onPointerDown: _down,
            onPointerMove: _move,
            onPointerUp: (e) => _release(e.pointer),
            onPointerCancel: (e) => _release(e.pointer, cancelled: true),
            child: shared
                ? ClipRect(
                    clipper: _SharedMastClip(_offset, _headerHeight),
                    child: widget.scrollBody!(scrollView, _collapseAt),
                  )
                : scrollView(_scroll, widget.slivers, active: true),
          );
          return Stack(
            children: [
              Positioned.fill(
                key: const ValueKey('tab-mast-background'),
                child: AnimatedBuilder(
                  animation: Listenable.merge([_offset, _pull]),
                  child: misty ? null : _MastWatermark(color: t.onLac),
                  builder: (_, watermark) {
                    final paper = t.background(widget.surface);
                    final seam = compact
                        ? TabChromeTokens.mistyGlowHeight
                        : _headerHeight + widget.seamOverlap;
                    final paperTop = seam - _offset.value + _pull.value;
                    return CustomPaint(
                      painter: _MastPainter(
                        tokens: t,
                        paper: paper,
                        seam: seam,
                        scroll: _offset.value,
                        pull: _pull.value,
                      ),
                      foregroundPainter: misty
                          ? null
                          : _MastPaperPainter(paper, paperTop),
                      child: watermark == null
                          ? null
                          : IgnorePointer(
                              child: Stack(
                                children: [
                                  Positioned(
                                    top: 0,
                                    right:
                                        TabChromeTokens.pageInset +
                                        widget.actions.length *
                                            TabChromeTokens.actionSize,
                                    child: Transform.translate(
                                      offset: Offset(
                                        0,
                                        paperTop -
                                            TabChromeTokens
                                                .watermarkVisibleHeight,
                                      ),
                                      child: watermark,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    );
                  },
                ),
              ),
              AnimatedBuilder(
                key: const ValueKey('tab-scroll-content'),
                animation: _pull,
                child: scrolling,
                builder: (_, child) => Transform.translate(
                  offset: Offset(0, _pull.value),
                  child: child,
                ),
              ),
              if (shared)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_offset, _pull]),
                    child: KeyedSubtree(key: _headerKey, child: header),
                    builder: (_, child) => Transform.translate(
                      offset: Offset(0, _pull.value - _offset.value),
                      child: child,
                    ),
                  ),
                ),
              if (widget.onRefresh != null)
                Positioned(
                  top: top,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(child: _wordmark(t, misty: misty)),
                ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: ValueListenableBuilder<double>(
                  valueListenable: _offset,
                  builder: (_, offset, _) {
                    final p = offset / _collapseAt;
                    final alpha = CompactBarProgress.background(p);
                    return AnnotatedRegion<SystemUiOverlayStyle>(
                      value: misty
                          ? (t.isDark
                                ? AppSystemUi.lightIcons
                                : AppSystemUi.darkIcons)
                          : AppSystemUi.lightIcons,
                      child: SizedBox(
                        height: _barBottom + TabChromeTokens.reverseRadius,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: IgnorePointer(
                                child: CustomPaint(
                                  painter: _CompactBackground(
                                    color: t
                                        .background(widget.surface)
                                        .withValues(alpha: alpha),
                                    gradient: misty
                                        ? null
                                        : TabChromeTokens.compactGradient(
                                            t,
                                            alpha,
                                          ),
                                    bottom: _barBottom,
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: top,
                              left: TabChromeTokens.pageInset,
                              right: widget.actions.isEmpty
                                  ? TabChromeTokens.pageInset
                                  : TabChromeTokens.actionInset,
                              height: NavOverlay.barHeight,
                              child: IgnorePointer(
                                ignoring: CompactBarProgress.smallTitle(p) == 0,
                                child: Opacity(
                                  opacity: CompactBarProgress.smallTitle(p),
                                  child: ValueListenableBuilder<bool>(
                                    valueListenable: _discussion,
                                    builder: (_, discussion, _) => Row(
                                      children: [
                                        if (widget.compactLeading != null) ...[
                                          widget.compactLeading!,
                                          const SizedBox(width: 10),
                                        ],
                                        Expanded(
                                          child:
                                              widget.compactTitle ??
                                              SlidingCompactTitle(
                                                title: widget.title,
                                                discussion: discussion,
                                              ),
                                        ),
                                        if (widget.compactAccessory != null)
                                          SingleMotionBuilder(
                                            value: discussion ? 1.0 : 0.0,
                                            motion: AppMotion.select,
                                            active: !_reduced,
                                            child: widget.compactAccessory,
                                            builder: (_, v, child) =>
                                                IgnorePointer(
                                                  ignoring: !discussion,
                                                  child: Opacity(
                                                    opacity: v.clamp(0.0, 1.0),
                                                    child: Transform.scale(
                                                      scale: .9 + .1 * v,
                                                      child: child,
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
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (widget.actions.isNotEmpty)
                Positioned(
                  top: top,
                  left: 0,
                  right: TabChromeTokens.pageInset,
                  height: _headerHeight + TabChromeTokens.maxPull,
                  child: Flow(
                    clipBehavior: Clip.none,
                    delegate: _TabActionsFlow(
                      scroll: _scroll,
                      mastOffset: shared ? _offset : null,
                      pull: _pull,
                      expandedY: widget.header == null
                          ? TabHeader.actionTop(context)
                          : _headerHeight -
                                top -
                                headerBottom -
                                TabChromeTokens.actionSize,
                    ),
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: widget.actions,
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SharedMastClip extends CustomClipper<Rect> {
  _SharedMastClip(this.offset, this.height) : super(reclip: offset);

  final ValueListenable<double> offset;
  final double height;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(
    0,
    (height - offset.value).clamp(0, size.height),
    size.width,
    size.height,
  );

  @override
  bool shouldReclip(_SharedMastClip oldClipper) =>
      height != oldClipper.height || offset != oldClipper.offset;
}

class _TabActionsFlow extends FlowDelegate {
  _TabActionsFlow({
    required this.scroll,
    required this.pull,
    required this.expandedY,
    this.mastOffset,
  }) : super(repaint: Listenable.merge([mastOffset ?? scroll, pull]));

  final ScrollController scroll;
  final ValueListenable<double>? mastOffset;
  final Animation<double> pull;
  final double expandedY;

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) =>
      constraints.loosen();

  @override
  void paintChildren(FlowPaintingContext context) {
    final childSize = context.getChildSize(0)!;
    // Viewport corrections happen during layout; follow the final painted offset.
    context.paintChild(
      0,
      transform: Matrix4.translationValues(
        context.size.width - childSize.width,
        math.max(
              TabChromeTokens.pinnedActionTop,
              expandedY -
                  (mastOffset?.value ??
                      (scroll.hasClients ? scroll.offset : 0)),
            ) +
            pull.value,
        0,
      ),
    );
  }

  @override
  bool shouldRepaint(_TabActionsFlow oldDelegate) =>
      scroll != oldDelegate.scroll ||
      mastOffset != oldDelegate.mastOffset ||
      pull != oldDelegate.pull ||
      expandedY != oldDelegate.expandedY;
}

class SlidingCompactTitle extends StatelessWidget {
  const SlidingCompactTitle({
    super.key,
    required this.title,
    required this.discussion,
  });
  final String title;
  final bool discussion;
  @override
  Widget build(BuildContext context) => SingleMotionBuilder(
    value: discussion ? 1.0 : 0.0,
    motion: AppMotion.select,
    active: !MediaQuery.disableAnimationsOf(context),
    builder: (_, v, _) {
      final travel = math.max(
        TabChromeTokens.titleTravel,
        MediaQuery.textScalerOf(context).scale(AppType.headline.fontSize!) *
            1.4,
      );
      final t = AppTokens.of(context);
      final style = AppType.headline.copyWith(
        color: t.style == AppearanceStyle.cinnabar ? t.onLac : t.text,
      );
      return ClipRect(
        child: SizedBox(
          height: travel,
          child: Stack(
            children: [
              Transform.translate(
                offset: Offset(0, -v * travel),
                child: Opacity(
                  opacity: (1 - v).clamp(0.0, 1.0),
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  ),
                ),
              ),
              Transform.translate(
                offset: Offset(0, (1 - v) * travel),
                child: Opacity(
                  opacity: v.clamp(0.0, 1.0),
                  child: Text(
                    '社区讨论',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _PullPhysics extends ClampingScrollPhysics {
  const _PullPhysics({required this.holding, super.parent});
  final bool Function() holding;
  @override
  _PullPhysics applyTo(ScrollPhysics? ancestor) =>
      _PullPhysics(holding: holding, parent: buildParent(ancestor));
  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) =>
      holding() ? 0 : super.applyPhysicsToUserOffset(position, offset);
}

class _MastPainter extends CustomPainter {
  const _MastPainter({
    required this.tokens,
    required this.paper,
    required this.seam,
    required this.scroll,
    required this.pull,
  });
  final AppTokens tokens;
  final Color paper;
  final double seam, scroll, pull;
  @override
  void paint(Canvas canvas, Size size) {
    final y = seam - scroll + pull;
    if (y <= 0) return;
    // Scale only the background layer. Content geometry never changes on pull.
    canvas.save();
    canvas.translate(0, -scroll);
    canvas.scale(1, (seam + pull) / seam);
    final rect = Rect.fromLTWH(0, 0, size.width, seam);
    final misty = tokens.style == AppearanceStyle.misty;
    if (misty) {
      canvas.drawRect(rect, Paint()..color = paper);
      for (final gradient in TabChromeTokens.mistGradients(tokens)) {
        canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));
      }
    } else {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, seam + TabChromeTokens.reverseRadius),
        Paint()..shader = tokens.lacGradient.createShader(rect),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MastPainter old) =>
      tokens != old.tokens ||
      paper != old.paper ||
      seam != old.seam ||
      scroll != old.scroll ||
      pull != old.pull;
}

class _MastWatermark extends StatelessWidget {
  const _MastWatermark({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: RepaintBoundary(
      child: ClipRect(
        child: Align(
          alignment: Alignment.topRight,
          heightFactor:
              TabChromeTokens.watermarkVisibleHeight /
              TabChromeTokens.watermarkSize,
          child: Text(
            'chh',
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontSize: TabChromeTokens.watermarkSize,
              height: 1,
              fontWeight: FontWeight.w800,
              letterSpacing: TabChromeTokens.watermarkLetterSpacing,
              color: color.withValues(alpha: TabChromeTokens.watermarkOpacity),
            ),
          ),
        ),
      ),
    ),
  );
}

class _MastPaperPainter extends CustomPainter {
  const _MastPaperPainter(this.paper, this.y);

  final Color paper;
  final double y;

  @override
  void paint(Canvas canvas, Size size) {
    if (y > -TabChromeTokens.reverseRadius) {
      final r = TabChromeTokens.reverseRadius;
      canvas.drawPath(
        Path()
          ..moveTo(0, y + r)
          ..quadraticBezierTo(0, y, r, y)
          ..lineTo(size.width - r, y)
          ..quadraticBezierTo(size.width, y, size.width, y + r)
          ..lineTo(size.width, size.height)
          ..lineTo(0, size.height)
          ..close(),
        Paint()..color = paper,
      );
    }
  }

  @override
  bool shouldRepaint(_MastPaperPainter old) => paper != old.paper || y != old.y;
}

class _CompactBackground extends CustomPainter {
  const _CompactBackground({
    required this.color,
    this.gradient,
    required this.bottom,
  });
  final Color color;
  final Gradient? gradient;
  final double bottom;
  @override
  void paint(Canvas canvas, Size size) {
    final r = TabChromeTokens.reverseRadius;
    final path = Path()
      ..lineTo(size.width, 0)
      ..lineTo(size.width, bottom + r)
      ..quadraticBezierTo(size.width, bottom, size.width - r, bottom)
      ..lineTo(r, bottom)
      ..quadraticBezierTo(0, bottom, 0, bottom + r)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..shader = gradient?.createShader(
          Rect.fromLTWH(0, 0, size.width, bottom),
        ),
    );
  }

  @override
  bool shouldRepaint(_CompactBackground old) =>
      color != old.color || gradient != old.gradient || bottom != old.bottom;
}
