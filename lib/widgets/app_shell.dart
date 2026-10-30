/// Application shell for the four primary destinations.
library;

import 'package:motor/motor.dart';
import '../design/icons.dart';
import '../design/motion.dart';
import '../ui/press.dart';
import '../design/typography.dart';
import 'package:flutter/material.dart';

import '../design/tokens.dart';
import 'large_title_scaffold.dart';
import '../ui/chrome_button.dart';
import 'expressive_controls.dart';

/// Primary destinations, presented by the bottom navigation.
enum AppDestination {
  feed('精选', AppIcons.tabHome),
  forums('版块', AppIcons.tabForums),
  messages('消息', AppIcons.tabMessages),
  me('我的', AppIcons.tabMe);

  const AppDestination(this.label, this.icon);
  final String label;
  final IconData icon;
}

class AppShell extends StatelessWidget {
  final String title;
  final AppDestination current;
  final Widget body;

  /// 顶栏右侧动作。消息入口由外壳统一提供,这里只放页面自己的动作。
  final List<Widget> actions;

  /// 顶栏下方常驻区域,例如分段控件或筛选条
  final Widget? subHeader;

  const AppShell({
    super.key,
    required this.title,
    required this.current,
    required this.body,
    this.actions = const [],
    this.subHeader,
  });

  @override
  Widget build(BuildContext context) {
    return LargeTitleScaffold(
      title: title,
      showBack: false,
      reserveNavigationBar: current == AppDestination.forums,
      surface: current == AppDestination.forums || current == AppDestination.me
          ? AppSurface.grouped
          : AppSurface.content,
      actions: actions,
      header: subHeader == null
          ? null
          : Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.screen,
                0,
                AppSpace.screen,
                10,
              ),
              child: subHeader,
            ),
      body: body,
    );
  }
}

/// Primary destinations stay one tap away.
class AppBottomNavigation extends StatelessWidget {
  final AppDestination current;
  final ValueChanged<AppDestination> onNavigate;

  /// "消息"图标上的未读数,0 时不显示
  final int messagesBadge;

  /// "我的"图标上的提示红点(有新版本)
  final bool meDot;
  const AppBottomNavigation({
    super.key,
    required this.current,
    required this.onNavigate,
    this.messagesBadge = 0,
    this.meDot = false,
  });
  static const destinations = [
    AppDestination.feed,
    AppDestination.forums,
    AppDestination.messages,
    AppDestination.me,
  ];

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final selected = destinations.indexOf(current);
    final index = selected < 0 ? 3 : selected;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final scale =
        MediaQuery.textScalerOf(context).scale(AppType.sizeFootnote) /
        AppType.sizeFootnote;
    final height = 68.0 + (scale - 1).clamp(0.0, 1.5) * 20;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(top: BorderSide(color: t.separator, width: .5)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final slot = constraints.maxWidth / 4;
              return Stack(
                children: [
                  SingleMotionBuilder(
                    value: index.toDouble(),
                    motion: AppMotion.select,
                    active: !reduced,
                    builder: (_, position, _) => Positioned(
                      left: slot * (position + .5) - 23,
                      top: 7,
                      width: 46,
                      height: 34,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: t.accentFill,
                          borderRadius: BorderRadius.circular(AppRadii.sm),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < destinations.length; i++)
                        Expanded(
                          child: Semantics(
                            selected: i == index,
                            child: PressScale(
                              onTap: () => onNavigate(destinations[i]),
                              semanticLabel: destinations[i].label,
                              scale: .94,
                              child: SizedBox(
                                height: height,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      height: 34,
                                      child: Center(
                                        child: SingleMotionBuilder(
                                          value: i == index ? 1.0 : 0.0,
                                          active: !reduced,
                                          motion: AppMotion.select,
                                          builder: (_, emphasis, _) =>
                                              Transform.scale(
                                                scale: 1 + .08 * emphasis,
                                                child: Stack(
                                                  clipBehavior: Clip.none,
                                                  children: [
                                                    Icon(
                                                      destinations[i].icon,
                                                      size: 24,
                                                      color: Color.lerp(
                                                        t.text3,
                                                        t.accent,
                                                        emphasis,
                                                      ),
                                                    ),
                                                    if (destinations[i] ==
                                                        AppDestination.messages)
                                                      Positioned(
                                                        top: -6,
                                                        left: 16,
                                                        child: CountBadge(
                                                          count: messagesBadge,
                                                        ),
                                                      ),
                                                    if (destinations[i] ==
                                                        AppDestination.me)
                                                      Positioned(
                                                        top: -1,
                                                        right: -3,
                                                        child: DotBadge(
                                                          visible: meDot,
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      destinations[i].label,
                                      style: TextStyle(
                                        fontSize: AppType.sizeFootnote,
                                        height: 1.4,
                                        fontWeight: i == index
                                            ? FontWeight.w600
                                            : FontWeight.w500,
                                        color: i == index ? t.accent : t.text2,
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
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
