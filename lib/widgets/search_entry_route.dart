/// Keeps the search input connected to the source action while the page arrives.
library;

import 'package:flutter/material.dart';
import '../design/motion.dart';

class SearchEntryRoute extends PageRouteBuilder<void> {
  SearchEntryRoute({required WidgetBuilder builder})
    : super(
        transitionDuration: AppMotion.revealDuration,
        reverseTransitionDuration: AppMotion.revealDuration,
        pageBuilder: (context, animation, secondary) => builder(context),
      );

  CurvedAnimation? _progress;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Keep direction memory when returning before the opening has completed.
    final progress = _progress ??= CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    if (MediaQuery.disableAnimationsOf(context)) {
      return FadeTransition(opacity: progress, child: child);
    }
    return FadeTransition(
      opacity: progress,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, .018),
          end: Offset.zero,
        ).animate(progress),
        child: RepaintBoundary(child: child),
      ),
    );
  }

  @override
  void dispose() {
    _progress?.dispose();
    super.dispose();
  }
}
