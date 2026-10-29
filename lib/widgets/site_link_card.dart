/// 正文里的站内帖子、文章卡片(设计稿已确认)
///
/// 一行高:左侧类型图标,中间标题(最多两行)加类型与日期,右侧细箭头。
/// 标题与时间由卡片出现时读取;取不到时保留链接文字,卡片照样能点。
library;

import 'package:flutter/material.dart';

import '../core/link_target.dart';
import '../data/link_preview_repository.dart';
import '../design/icons.dart';
import '../design/motion.dart';
import '../design/shapes.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../di.dart';
import '../models/models.dart';
import '../ui/press.dart';
import 'link_opener.dart';

typedef SiteLinkOpener = void Function(LinkTarget target, String title);

class SiteLinkCard extends StatefulWidget {
  final SiteLinkBlock block;

  /// 默认用全局实例;测试里注入 fake
  final LinkPreviewRepository? repository;

  /// 默认进对应的帖子页或文章页;测试里注入回调
  final SiteLinkOpener? onOpen;

  const SiteLinkCard({
    super.key,
    required this.block,
    this.repository,
    this.onOpen,
  });

  @override
  State<SiteLinkCard> createState() => _SiteLinkCardState();
}

enum _Phase { loading, loaded, failed }

class _SiteLinkCardState extends State<SiteLinkCard> {
  static const _iconBox = 36.0;

  LinkPreview? _preview;
  var _phase = _Phase.loading;

  LinkTarget get _target => widget.block.target;
  LinkPreviewRepository get _repo => widget.repository ?? linkPreviewRepo;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant SiteLinkCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.block.target.key != _target.key) _load();
  }

  void _load() {
    // 已缓存的直接用,滚回来不闪读取态
    final hit = _repo.cached(_target);
    if (hit != null) {
      _preview = hit;
      _phase = _Phase.loaded;
      return;
    }
    _preview = null;
    _phase = _repo.hasFailed(_target) ? _Phase.failed : _Phase.loading;
    if (_phase == _Phase.failed) return;
    final key = _target.key;
    _repo.preview(_target).then((value) {
      // 卡片已滚走或换了目标时丢弃迟到的结果
      if (!mounted || key != _target.key) return;
      setState(() {
        _preview = value;
        _phase = value == null ? _Phase.failed : _Phase.loaded;
      });
    });
  }

  /// 链接文字;文字就是网址时用地址末段,不显示整串网址
  String get _fallbackTitle {
    if (widget.block.label.isNotEmpty) return widget.block.label;
    final segments = _target.uri.pathSegments.where((s) => s.isNotEmpty);
    return segments.isEmpty ? _target.uri.toString() : segments.last;
  }

  bool get _isThread => _preview?.isThread ?? _target is ThreadLink;

  void _open() {
    final title = _preview?.title ?? widget.block.label;
    final onOpen = widget.onOpen;
    if (onOpen != null) {
      onOpen(_target, title);
    } else {
      openLinkTarget(context, _target, title: title);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final kind = _isThread ? '帖子' : '文章';
    final title = _preview?.title ?? _fallbackTitle;
    return PressScale(
      onTap: _open,
      scale: 0.97,
      semanticLabel: '$kind $title',
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: t.surface,
          shape: appShape(AppRadii.sm).copyWith(
            side: BorderSide(color: t.separator, width: AppSpace.hairline),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              _icon(t),
              const SizedBox(width: 12),
              Expanded(child: _texts(context, t, kind, title)),
              const SizedBox(width: 8),
              Icon(AppIcons.forward, size: 16, color: t.text3),
            ],
          ),
        ),
      ),
    );
  }

  /// 失败时图标变灰,说明这张卡片没取到信息
  Widget _icon(AppTokens t) {
    final failed = _phase == _Phase.failed;
    return Container(
      width: _iconBox,
      height: _iconBox,
      decoration: ShapeDecoration(
        color: failed ? t.fill : t.accentFill,
        shape: appShape(AppRadii.xs),
      ),
      child: Icon(
        _isThread ? AppIcons.thread : AppIcons.article,
        size: 18,
        color: failed ? t.text2 : t.accent,
      ),
    );
  }

  Widget _texts(BuildContext context, AppTokens t, String kind, String title) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final loading = _phase == _Phase.loading;
    return AnimatedSwitcher(
      duration: reduced ? AppMotion.reducedFade : AppMotion.fade,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.centerLeft,
        children: [...previous, ?current],
      ),
      child: Column(
        key: ValueKey(_phase),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            maxLines: loading ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: AppType.callout.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.35,
              color: loading ? t.text2 : t.text,
            ),
          ),
          const SizedBox(height: 3),
          _meta(t, kind),
        ],
      ),
    );
  }

  Widget _meta(AppTokens t, String kind) {
    final time = _preview?.time;
    return Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          kind,
          style: AppType.caption.copyWith(
            color: _phase == _Phase.failed ? t.text2 : t.accent,
          ),
        ),
        if (_phase == _Phase.loading)
          Container(
            key: const ValueKey('site-card-date-placeholder'),
            width: 72,
            height: 10,
            decoration: ShapeDecoration(
              color: t.fill,
              shape: appShape(AppRadii.bar),
            ),
          )
        else if (time != null)
          Text(_date(time), style: AppType.footnote.copyWith(color: t.text2)),
      ],
    );
  }

  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
