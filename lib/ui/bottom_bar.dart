/// 页面底部固定操作区:surface 底与留白,避开底部安全区
library;

import 'package:flutter/material.dart';

import '../design/thread_page_tokens.dart';
import '../design/tokens.dart';

class BottomBar extends StatelessWidget {
  final Widget child;
  const BottomBar({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: ThreadPageTokens.readingBarFadeHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [t.surface.withValues(alpha: 0), t.surface],
              ),
            ),
          ),
        ),
        ColoredBox(
          color: t.surface,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.rowInset,
                0,
                AppSpace.rowInset,
                ThreadPageTokens.discussionBarBottomPadding,
              ),
              child: child,
            ),
          ),
        ),
      ],
    );
  }
}
