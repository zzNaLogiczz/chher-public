/// 非不透明的侧抽屉保留底层页面与阅读状态。
library;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../design/motion.dart';
import '../design/tokens.dart';

Future<void> pushSideDrawer(
  BuildContext context, {
  required WidgetBuilder builder,
  required String barrierLabel,
}) {
  final t = AppTokens.of(context);
  final reduced = MediaQuery.disableAnimationsOf(context);
  return Navigator.of(context).push(
    _SideDrawerRoute(
      builder: builder,
      barrierColor: t.scrim,
      barrierLabel: barrierLabel,
      reduced: reduced,
    ),
  );
}

class _SideDrawerRoute extends PageRouteBuilder<void> {
  _SideDrawerRoute({
    required WidgetBuilder builder,
    required super.barrierColor,
    required super.barrierLabel,
    required this.reduced,
  }) : super(
         opaque: false,
         barrierDismissible: true,
         transitionDuration: reduced ? Duration.zero : AppMotion.sheetDuration,
         reverseTransitionDuration: reduced
             ? Duration.zero
             : AppMotion.revealDuration,
         pageBuilder: (context, _, _) => builder(context),
         transitionsBuilder: (_, animation, _, child) => SlideTransition(
           position: Tween(
             begin: const Offset(1, 0),
             end: Offset.zero,
           ).animate(animation),
           child: child,
         ),
       );

  final bool reduced;

  @override
  Simulation? createSimulation({required bool forward}) => reduced
      ? null
      : SpringSimulation(
          (forward ? AppMotion.sheet : AppMotion.reveal).description,
          controller!.value,
          forward ? 1 : 0,
          controller!.velocity,
          snapToEnd: true,
        );
}
