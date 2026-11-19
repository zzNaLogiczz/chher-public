import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../data/image_disk_cache.dart';
import '../design/brand.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../ui/feedback.dart';
import 'cached_net_image.dart';
import 'net_image.dart';
import 'viewport_ticker_mode.dart';

/// 圆形底色始终保留在头像下方，包括透明图片和淡入期间。
class AvatarFrame extends StatelessWidget {
  final double size;
  final Widget child;

  const AvatarFrame({super.key, required this.size, required this.child});

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: ClipOval(
      child: ColoredBox(color: AppTokens.of(context).surface2, child: child),
    ),
  );
}

/// 头像加载和失败时显示应用标志；个人主页可按地址单独刷新。
class AvatarImage extends StatefulWidget {
  final String? url;
  final String name;
  final double size;
  final bool refreshable;
  final bool lazy;
  const AvatarImage({
    super.key,
    this.url,
    this.name = '',
    required this.size,
    this.refreshable = false,
    this.lazy = false,
  });

  @override
  State<AvatarImage> createState() => _AvatarImageState();
}

class _AvatarImageState extends State<AvatarImage> {
  int _revision = 0;
  bool _visible = false;
  bool _refreshing = false;
  bool _failed = false;
  bool _completionScheduled = false;
  bool _checkingCache = false;
  ImageProvider<Object>? _provider;
  (String, int, int)? _providerSpec;
  String? get _url =>
      widget.url?.trim().isNotEmpty == true ? widget.url!.trim() : null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ModalRoute.isCurrentOf(context) ?? true) _restoreCachedAvatar();
  }

  Future<void> _restoreCachedAvatar() async {
    final spec = _providerSpec;
    if (!_failed || _checkingCache || spec == null) return;
    _checkingCache = true;
    try {
      final bytes = await imageDiskCache.read(spec.$1);
      if (!mounted || spec != _providerSpec || spec.$3 != _revision) return;
      if (bytes != null) {
        // A detail page may have filled this cache; recovery must never retry HTTP.
        setState(() {
          _provider = ResizeImage(MemoryImage(bytes), width: spec.$2);
          _failed = false;
        });
      }
    } finally {
      _checkingCache = false;
    }
  }

  @override
  void didUpdateWidget(covariant AvatarImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _revision++;
      _visible = false;
      _refreshing = false;
      _failed = false;
      _completionScheduled = false;
    }
  }

  Future<void> _refresh() async {
    final url = _url;
    if (_refreshing || url == null) return;
    final revision = ++_revision;
    setState(() {
      _refreshing = true;
      _failed = false;
      _completionScheduled = false;
    });
    try {
      await ChhCachedImage.invalidate(url);
      if (mounted && revision == _revision) setState(() {});
    } catch (_) {
      _finish(revision, failed: true);
    }
  }

  Future<void> _showRefreshMenu() async {
    final avatar = context.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final url = _url;
    final selected = await showMenu<bool>(
      context: context,
      position: RelativeRect.fromSize(
        avatar.localToGlobal(Offset.zero, ancestor: overlay) & avatar.size,
        overlay.size,
      ),
      popUpAnimationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : AnimationStyle(
              duration: AppMotion.revealDuration,
              curve: AppMotion.revealCurve,
            ),
      items: const [PopupMenuItem(value: true, child: Text('刷新头像'))],
    );
    if (mounted && selected == true && url == _url) await _refresh();
  }

  void _finish(int revision, {bool failed = false}) {
    if (revision != _revision ||
        _completionScheduled ||
        (!_refreshing && !failed) ||
        (failed && _failed)) {
      return;
    }
    final manual = _refreshing;
    _completionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || revision != _revision) return;
      setState(() {
        _refreshing = false;
        _failed = failed;
        _completionScheduled = false;
      });
      if (failed && manual) AppToast.show(context, '头像加载失败，请重试');
    });
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.lazy && !_visible ? null : _url;
    final revision = _revision;
    final size = widget.size;
    final pixels = boundedImageDecodeWidth(
      size,
      MediaQuery.devicePixelRatioOf(context),
    );
    // 按钮和错误反馈的重建不能隐式重试；仅地址、尺寸或手动刷新改变时解析。
    if (url != null && _providerSpec != (url, pixels, revision)) {
      _providerSpec = (url, pixels, revision);
      _provider = boundedNetworkImage(url, pixels);
    }
    final fallback = Image.asset(
      appLogoAsset,
      key: const ValueKey('avatar-logo'),
      width: size,
      height: size,
      cacheWidth: pixels,
      fit: BoxFit.cover,
      excludeFromSemantics: true,
    );
    final avatar = ExcludeSemantics(
      child: AvatarFrame(
        size: size,
        child: url == null || _failed
            ? fallback
            : ViewportTickerMode(
                // Lazy avatars already passed visibility detection; avoid a
                // second inherited-mode change retrying an immediate failure.
                initiallyVisible: true,
                child: Image(
                  key: ValueKey((url, revision)),
                  image: _provider!,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  excludeFromSemantics: true,
                  frameBuilder: (_, child, frame, synchronous) {
                    if (synchronous || frame != null) {
                      _finish(revision);
                      if (synchronous) return child;
                      return TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: AppMotion.mediaFade,
                        curve: AppMotion.mediaFadeCurve,
                        builder: (_, opacity, image) => Stack(
                          fit: StackFit.expand,
                          children: [
                            if (opacity < 1)
                              Opacity(opacity: 1 - opacity, child: fallback),
                            Opacity(opacity: opacity, child: image),
                          ],
                        ),
                        child: child,
                      );
                    }
                    return fallback;
                  },
                  errorBuilder: (_, _, _) {
                    _finish(revision, failed: true);
                    return fallback;
                  },
                ),
              ),
      ),
    );
    if (widget.lazy && !_visible) {
      return _VisibleAvatar(
        onVisible: () {
          if (mounted && !_visible) {
            setState(() => _visible = true);
          }
        },
        child: avatar,
      );
    }
    if (!widget.refreshable || url == null) return avatar;
    return Semantics(
      label: _refreshing ? '头像刷新中' : '头像',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: _refreshing ? null : _showRefreshMenu,
        child: avatar,
      ),
    );
  }
}

// Cached row layers can scroll into view without repainting their children.
class _VisibleAvatar extends StatefulWidget {
  const _VisibleAvatar({required this.onVisible, required this.child});
  final VoidCallback onVisible;
  final Widget child;

  @override
  State<_VisibleAvatar> createState() => _VisibleAvatarState();
}

class _VisibleAvatarState extends State<_VisibleAvatar> {
  final _positions = <ScrollPosition>{};
  bool _scheduled = false;
  bool _notified = false;
  bool _active = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _active =
        (ModalRoute.isCurrentOf(context) ?? true) &&
        TickerMode.valuesOf(context).enabled;
    // Depend on the nearest scrollable; nested headers may move the outer one.
    Scrollable.maybeOf(context);
    for (final position in _positions) {
      position.removeListener(_scheduleCheck);
    }
    _positions.clear();
    context.visitAncestorElements((ancestor) {
      if (ancestor is StatefulElement && ancestor.state is ScrollableState) {
        _positions.add((ancestor.state as ScrollableState).position);
      }
      return true;
    });
    for (final position in _positions) {
      position.addListener(_scheduleCheck);
    }
    _scheduleCheck();
  }

  void _scheduleCheck() {
    if (_scheduled || _notified || !_active) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted || _notified || !_active) return;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) return;
      for (
        var ancestor = box.parent;
        ancestor != null;
        ancestor = ancestor.parent
      ) {
        if (ancestor is! RenderAbstractViewport) continue;
        final RenderObject viewport = ancestor;
        if (viewport is RenderBox && viewport.hasSize) {
          final bounds = MatrixUtils.transformRect(
            box.getTransformTo(viewport),
            box.paintBounds,
          );
          if (!bounds.overlaps(viewport.paintBounds)) return;
        }
      }
      _notified = true;
      widget.onVisible();
    });
  }

  @override
  void dispose() {
    for (final position in _positions) {
      position.removeListener(_scheduleCheck);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
