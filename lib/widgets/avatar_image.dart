import 'package:flutter/material.dart';

import '../design/brand.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../ui/feedback.dart';
import '../ui/press.dart';
import 'cached_net_image.dart';
import 'net_image.dart';

/// 头像加载和失败时使用品牌图标；个人主页可按地址单独刷新。
class AvatarImage extends StatefulWidget {
  final String? url;
  final double size;
  final bool refreshable;
  const AvatarImage({
    super.key,
    this.url,
    required this.size,
    this.refreshable = false,
  });

  @override
  State<AvatarImage> createState() => _AvatarImageState();
}

class _AvatarImageState extends State<AvatarImage> {
  int _revision = 0;
  bool _refreshing = false;
  bool _failed = false;
  bool _completionScheduled = false;
  ImageProvider<Object>? _provider;
  (String, int, int)? _providerSpec;
  String? get _url =>
      widget.url?.trim().isNotEmpty == true ? widget.url!.trim() : null;

  @override
  void didUpdateWidget(covariant AvatarImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _revision++;
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
    final t = AppTokens.of(context);
    final url = _url;
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
      width: size,
      height: size,
      fit: BoxFit.cover,
      cacheWidth: pixels,
      excludeFromSemantics: true,
    );
    final avatar = ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: url == null || _failed
            ? fallback
            : Image(
                key: ValueKey((url, revision)),
                image: _provider!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                excludeFromSemantics: true,
                frameBuilder: (_, child, frame, synchronous) {
                  if (synchronous || frame != null) {
                    _finish(revision);
                    return child;
                  }
                  return fallback;
                },
                errorBuilder: (_, _, _) {
                  _finish(revision, failed: true);
                  return fallback;
                },
              ),
      ),
    );
    if (!widget.refreshable || url == null) return avatar;
    return Tooltip(
      message: '刷新头像',
      child: PressScale(
        onTap: _refreshing ? null : _refresh,
        semanticLabel: _refreshing ? '头像刷新中' : '刷新头像',
        child: Stack(
          children: [
            avatar,
            Positioned(
              right: 0,
              bottom: 0,
              child: ExcludeSemantics(
                child: Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: t.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: t.separator, width: .5),
                  ),
                  child: _refreshing
                      ? const SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        )
                      : Icon(AppIcons.refresh, size: 16, color: t.text2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
