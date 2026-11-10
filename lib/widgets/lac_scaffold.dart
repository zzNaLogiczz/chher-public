/// 一级页漆面骨架:漆面渐变铺满上方 + 纸面圆角悬浮遮盖(朱漆红 v2)
///
/// 精选/版块/消息/我的四个一级页共用:标题与 mast 内容住在漆面上
/// (奶白文字),正文区是 [PaperSheet]——上圆角纸面盖在漆面上,
/// 接缝动作与设计稿一致。二级页不使用本骨架,保持纸面。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/tokens.dart';
import '../ui/nav_bar.dart';

/// 漆面一级页骨架。
class LacScaffold extends StatefulWidget {
  final String title;

  /// 大标题上方的眉题,例如精选页的日期
  final String? eyebrow;

  /// 顶栏右侧的漆面圆钮/胶囊组(调用方传 onLac 变体)
  final List<Widget> actions;

  /// 大标题下方的漆面常驻内容(我的=身份卡,消息=分段,版块=搜索+分区)
  final Widget? mast;

  /// 漆面在标题区之下再露出的高度;纸面圆角从这里开始
  final double seamGap;

  /// 整头固定(我的页定稿):标题/身份卡/岛不随内容上收,正文独立滚动
  final bool pinned;

  /// 纸面内容(自身带滚动)
  final Widget body;

  const LacScaffold({
    super.key,
    required this.title,
    required this.body,
    this.eyebrow,
    this.actions = const [],
    this.mast,
    this.seamGap = 20,
    this.pinned = false,
  });

  @override
  State<LacScaffold> createState() => _LacScaffoldState();
}

class _LacScaffoldState extends State<LacScaffold> {
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
    final top = MediaQuery.paddingOf(context).top;
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureTitle());
    // 漆面在上(白图标);纸面滚到顶栏之后按纸面亮度切换
    final paperOverlay = t.isDark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;
    final titleHeader = KeyedSubtree(
      key: _titleKey,
      child: LargeTitleHeader(
        title: widget.title,
        eyebrow: widget.eyebrow,
        accessory: widget.actions.isEmpty
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < widget.actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    widget.actions[i],
                  ],
                ],
              ),
        onLac: true,
      ),
    );

    final content = widget.pinned
        ? // 整头固定(我的页定稿):大标题与身份卡不许上收,正文独立滚动
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: top + NavOverlay.barHeight),
              titleHeader,
              if (widget.mast != null) mastBox(),
              SizedBox(height: widget.seamGap),
              Expanded(child: PaperSheet(child: widget.body)),
            ],
          )
        : NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              // 只看外层(大标题所在)的滚动
              if (notification.depth == 0 &&
                  notification.metrics.axis == Axis.vertical) {
                _offset.value = notification.metrics.pixels;
              }
              return false;
            },
            child: NestedScrollView(
              physics: const BouncingScrollPhysics(),
              headerSliverBuilder: (context, _) => [
                SliverToBoxAdapter(
                  child: SizedBox(height: top + NavOverlay.barHeight),
                ),
                SliverToBoxAdapter(child: titleHeader),
                if (widget.mast != null)
                  SliverToBoxAdapter(child: mastBox()),
                // 漆面脚:纸面圆角从这里开始,红从圆角两侧露出来
                SliverToBoxAdapter(child: SizedBox(height: widget.seamGap)),
              ],
              body: PaperSheet(child: widget.body),
            ),
          );
    return ValueListenableBuilder<double>(
      valueListenable: _offset,
      builder: (context, offset, child) =>
          AnnotatedRegion<SystemUiOverlayStyle>(
            // 漆面在上(白图标);纸面滚到顶栏之后按纸面亮度切换
            value: offset >= _collapseAt ? paperOverlay : SystemUiOverlayStyle.light,
            child: child!,
          ),
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: t.lacGradient),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              // chh 水印:压在漆面右上角,滚动内容从它上面划过
              const Positioned(top: 4, right: -14, child: _Watermark()),
              if (widget.pinned) Positioned.fill(child: content) else content,
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: NavOverlay(
                  inlineTitle: widget.title,
                  scrollOffset: _offset,
                  collapseAt: _collapseAt,
                  background: t.bg,
                  onLac: true,
                  // 圆钮只住大标题右侧(accessory),随标题滚走——设计稿
                  // navtop 非粘性,折叠后顶部只有小标题,不出现第二个钮
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// mast 容器:统一高度,内容顶对齐,不足留白,超出裁剪
  Widget mastBox() => SizedBox(
    height: AppSpace.mastRegion,
    child: ClipRect(
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minHeight: 0,
        maxHeight: double.infinity,
        child: widget.mast,
      ),
    ),
  );
}

/// 纸面:上圆角盖住漆面,红调投影让接缝"浮"起来
class PaperSheet extends StatelessWidget {
  final Widget child;
  const PaperSheet({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.bg,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadii.paper),
        ),
        boxShadow: t.paperShadow,
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadii.paper),
        ),
        child: child,
      ),
    );
  }
}

/// 漆面水印:大字 chh,奶白 10%,溢出右缘
class _Watermark extends StatelessWidget {
  const _Watermark();

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return IgnorePointer(
      child: Opacity(
        opacity: .1,
        child: Text(
          'chh',
          maxLines: 1,
          style: TextStyle(
            fontSize: LacquerMarks.watermark,
            fontWeight: FontWeight.w800,
            letterSpacing: -5,
            height: 1,
            color: t.onLac,
          ),
        ),
      ),
    );
  }
}
