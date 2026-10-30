/// 非不透明的侧抽屉保留底层页面与阅读状态。
library;

import 'package:flutter/material.dart';

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
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: t.scrim,
      barrierDismissible: true,
      barrierLabel: barrierLabel,
      transitionDuration: reduced ? Duration.zero : AppMotion.sheetDuration,
      reverseTransitionDuration: reduced
          ? Duration.zero
          : AppMotion.revealDuration,
      pageBuilder: (context, _, _) => builder(context),
      transitionsBuilder: (_, animation, _, child) => SlideTransition(
        position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(
          CurvedAnimation(
            parent: animation,
            curve: AppMotion.sheetCurve,
            reverseCurve: Curves.easeInCubic,
          ),
        ),
        child: child,
      ),
    ),
  );
}
