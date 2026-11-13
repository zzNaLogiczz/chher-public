/// 二级与模态页骨架:与浮动顶栏共用几何,正文始终位于顶栏下方。
library;

import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../design/typography.dart';
import '../ui/chrome_button.dart';
import '../ui/nav_bar.dart';
import 'expressive_controls.dart';

class CompactScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget> actions;
  final bool showBack;
  final Widget? bottomNavigationBar;
  final PreferredSizeWidget? bottom;
  final bool centerTitle;
  final Color? background;
  final bool resizeToAvoidBottomInset;

  const CompactScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions = const [],
    this.showBack = true,
    this.bottomNavigationBar,
    this.bottom,
    this.centerTitle = false,
    this.background,
    this.resizeToAvoidBottomInset = true,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final top = MediaQuery.paddingOf(context).top;
    final headerHeight = top + NavOverlay.barHeight;
    final bottomHeight = bottom?.preferredSize.height ?? 0;
    final color = background ?? t.bg;
    return Scaffold(
      backgroundColor: color,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      bottomNavigationBar: bottomNavigationBar,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: EdgeInsets.only(top: headerHeight + bottomHeight),
            child: Builder(
              builder: (bodyContext) => MediaQuery.removePadding(
                context: bodyContext,
                removeTop: true,
                child: body,
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ColoredBox(
              color: color,
              child: Padding(
                padding: EdgeInsets.only(top: top),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: NavOverlay.barHeight,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: NavigationToolbar(
                          centerMiddle: centerTitle,
                          middleSpacing: 8,
                          leading: showBack
                              ? ChromeButton(
                                  icon: AppIcons.back,
                                  tooltip: '返回',
                                  onPressed: () =>
                                      Navigator.of(context).maybePop(),
                                )
                              : null,
                          middle: Semantics(
                            header: true,
                            child: Text(
                              title,
                              key: const ValueKey('compact-scaffold-title'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.headline.copyWith(color: t.text),
                            ),
                          ),
                          trailing: actions.isEmpty
                              ? null
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    for (
                                      var i = 0;
                                      i < actions.length;
                                      i++
                                    ) ...[
                                      if (i > 0) const SizedBox(width: 6),
                                      actions[i],
                                    ],
                                  ],
                                ),
                        ),
                      ),
                    ),
                    if (bottom != null)
                      SizedBox(height: bottomHeight, child: bottom),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
