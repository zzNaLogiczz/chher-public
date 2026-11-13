/// 形状:rMd 及以上使用连续曲率圆角(规格 §5.3)。
/// 若真机 Raster 超预算,把 [kContinuousCorners] 改为 false 即可整体退回普通圆角。
library;

import 'package:flutter/widgets.dart';

const bool kContinuousCorners = true;

OutlinedBorder appShape(double radius) => kContinuousCorners
    ? RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(radius))
    : RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));

/// 按 [appShape] 的曲率裁剪子树
class AppClip extends StatelessWidget {
  final double? radius;
  final BorderRadius? borderRadius;
  final Widget child;
  const AppClip({super.key, required double this.radius, required this.child})
    : borderRadius = null;

  const AppClip.borderRadius({
    super.key,
    required BorderRadius this.borderRadius,
    required this.child,
  }) : radius = null;

  @override
  Widget build(BuildContext context) {
    final br = borderRadius ?? BorderRadius.circular(radius!);
    return kContinuousCorners
        ? ClipRSuperellipse(borderRadius: br, child: child)
        : ClipRRect(borderRadius: br, child: child);
  }
}
