import 'package:flutter/material.dart';

/// Keep platform scroll physics, without stretching or glowing at the edges.
/// Custom header pulls and horizontal rubber bands own their own transforms.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}
