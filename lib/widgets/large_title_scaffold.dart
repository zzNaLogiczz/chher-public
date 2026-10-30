/// 大标题页面骨架:浮动顶栏 + 随内容滚走的大标题(规格 §6.1)
library;

import 'package:flutter/material.dart';
import '../design/tokens.dart';
import '../ui/chrome_button.dart';
import '../ui/nav_bar.dart';
import 'expressive_controls.dart';

class LargeTitleScaffold extends StatefulWidget {
  final String title;
  final Widget body;

  /// 是否显示返回圆钮。由调用方明确指定,不再从 Navigator.canPop 推断;
  /// 四个根分栏传 false。
  final bool showBack;

  /// 为带固定工具栏的正文预留顶栏空间,不随外层标题滚动消失。
  final bool reserveNavigationBar;

  /// 顶栏右侧的圆钮或胶囊组
  final List<Widget> actions;

  /// 与大标题同一行右侧的圆钮(根分栏用)
  final Widget? titleAccessory;

  /// 大标题上方的眉题,例如日期
  final String? eyebrow;

  /// 大标题下方随内容滚动的区域:分段、搜索框、选择按钮
  final Widget? header;
  final AppSurface surface;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;

  const LargeTitleScaffold({
    super.key,
    required this.title,
    required this.body,
    this.showBack = true,
    this.reserveNavigationBar = false,
    this.actions = const [],
    this.titleAccessory,
    this.eyebrow,
    this.header,
    this.surface = AppSurface.content,
    this.bottomNavigationBar,
    this.floatingActionButton,
  });

  @override
  State<LargeTitleScaffold> createState() => _LargeTitleScaffoldState();
}

class _LargeTitleScaffoldState extends State<LargeTitleScaffold> {
  final _offset = ValueNotifier<double>(0);
  final _titleKey = GlobalKey();
  double _collapseAt = double.infinity;

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  // 大标题行的实际高度决定小标题出现的位置;字号变化后重新量
  void _measureTitle() {
    final height = _titleKey.currentContext?.size?.height;
    if (height != null && height != _collapseAt && mounted) {
      setState(() => _collapseAt = height);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final background = t.background(widget.surface);
    final top = MediaQuery.paddingOf(context).top;
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureTitle());
    return Scaffold(
      backgroundColor: background,
      bottomNavigationBar: widget.bottomNavigationBar,
      floatingActionButton: widget.floatingActionButton,
      body: Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(
              top: widget.reserveNavigationBar ? top + NavOverlay.barHeight : 0,
            ),
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                // 只看外层(大标题所在)的滚动;内层列表的滚动发生在大标题收起之后
                if (notification.depth == 0 &&
                    notification.metrics.axis == Axis.vertical) {
                  _offset.value = notification.metrics.pixels;
                }
                return false;
              },
              child: NestedScrollView(
                physics: const BouncingScrollPhysics(),
                headerSliverBuilder: (context, _) => [
                  if (!widget.reserveNavigationBar)
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _BarSpacer(top + NavOverlay.barHeight),
                    ),
                  SliverToBoxAdapter(
                    child: KeyedSubtree(
                      key: _titleKey,
                      child: LargeTitleHeader(
                        title: widget.title,
                        eyebrow: widget.eyebrow,
                        accessory: widget.titleAccessory,
                      ),
                    ),
                  ),
                  if (widget.header != null)
                    SliverToBoxAdapter(child: widget.header),
                ],
                body: widget.body,
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: NavOverlay(
              fadeBelowBar: !widget.reserveNavigationBar,
              leading: widget.showBack
                  ? ChromeButton(
                      icon: AppIcons.back,
                      tooltip: '返回',
                      onPressed: () => Navigator.of(context).maybePop(),
                    )
                  : null,
              actions: widget.actions,
              inlineTitle: widget.title,
              scrollOffset: _offset,
              collapseAt: _collapseAt,
              background: background,
            ),
          ),
        ],
      ),
    );
  }
}

/// 顶栏占位:固定高度、透明,让正文在按钮行下方停住
class _BarSpacer extends SliverPersistentHeaderDelegate {
  final double extent;
  const _BarSpacer(this.extent);

  @override
  double get minExtent => extent;
  @override
  double get maxExtent => extent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      const SizedBox.expand();

  @override
  bool shouldRebuild(covariant _BarSpacer oldDelegate) =>
      oldDelegate.extent != extent;
}
