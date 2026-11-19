import 'package:flutter/material.dart';

import '../design/motion.dart';
import 'chhers_loader.dart';
import 'expressive_controls.dart';

/// Retains a visible waiting mark for its exit before revealing the result.
class ChhersLoadingTransition extends StatefulWidget {
  const ChhersLoadingTransition({
    super.key,
    required this.child,
    this.size = ChhersLoaderSize.page,
    this.placeholderBuilder,
    this.animateOnMount = false,
    this.contentRevision,
    this.onContentReady,
  }) : sliver = false;

  const ChhersLoadingTransition.sliver({
    super.key,
    required this.child,
    required this.placeholderBuilder,
    this.contentRevision,
  }) : onContentReady = null,
       sliver = true,
       size = ChhersLoaderSize.page,
       animateOnMount = false;

  /// A null child indicates an outstanding load.
  final Widget? child;
  final ChhersLoaderSize size;
  final Widget Function(Widget indicator)? placeholderBuilder;
  final bool sliver;
  final bool animateOnMount;

  final Object? contentRevision;

  /// Runs after the result's first layout, including after a visible exit.
  final VoidCallback? onContentReady;

  @override
  State<ChhersLoadingTransition> createState() =>
      _ChhersLoadingTransitionState();
}

class _ChhersLoadingTransitionState extends State<ChhersLoadingTransition>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _exit = AnimationController(
    vsync: this,
    duration: AppMotion.loadingOut,
    value: 1,
    animationBehavior: AnimationBehavior.preserve,
  );

  bool _showing = false;
  bool _reveal = false;
  bool _contentReady = false;
  late bool _foreground = _isForeground(WidgetsBinding.instance.lifecycleState);

  bool _isForeground(AppLifecycleState? state) =>
      state == null || state == AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _exit.addStatusListener((status) {
      if (status == AnimationStatus.dismissed) {
        setState(() {
          _showing = false;
          _reveal = true;
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant ChhersLoadingTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.child == null && oldWidget.child != null) {
      _reveal = false;
      _contentReady = false;
      if (_showing) {
        _exit.forward();
      } else {
        _exit.value = 1;
      }
    } else if (widget.child != null && oldWidget.child == null) {
      if (_showing && _foreground && TickerMode.valuesOf(context).enabled) {
        _exit.reverse();
      } else {
        _showing = false;
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!TickerMode.valuesOf(context).enabled) _skipExit();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = _isForeground(state);
    if (!_foreground) setState(_skipExit);
  }

  void _skipExit() {
    if (widget.child == null || !_showing) return;
    _exit.stop();
    _showing = false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _exit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    if (child == null || _showing) {
      final indicator = FadeTransition(
        opacity: _exit,
        child: ChhersLoader(
          size: widget.size,
          animate: child == null,
          onVisible: () => _showing = true,
        ),
      );
      return widget.placeholderBuilder?.call(indicator) ??
          Center(child: indicator);
    }

    if (!_contentReady && widget.onContentReady != null) {
      _contentReady = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.child != null && !_showing) {
          widget.onContentReady?.call();
        }
      });
    }

    return ExpressivePageReveal(
      active: true,
      sliver: widget.sliver,
      animateOnMount: _reveal || widget.animateOnMount,
      revision: widget.contentRevision,
      child: child,
    );
  }
}
