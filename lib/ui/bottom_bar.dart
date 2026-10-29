/// 页面底部固定操作区:surface 底 + 顶部 0.5px 分隔线,避开底部安全区
library;

import 'package:flutter/material.dart';

import '../design/tokens.dart';

class BottomBar extends StatelessWidget {
  final Widget child;
  const BottomBar({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(
          top: BorderSide(color: t.separator, width: AppSpace.hairline),
        ),
      ),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: child,
          ),
        ),
      ),
    );
  }
}
