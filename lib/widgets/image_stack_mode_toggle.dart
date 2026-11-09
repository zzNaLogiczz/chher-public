import 'package:flutter/material.dart';

import '../design/motion.dart';
import '../design/tokens.dart';
import '../ui/press.dart';

/// Three retained rectangles interpolate from a fan to horizontal list lines.
/// The painted control stays small; its transparent touch region is 44dp.
class ImageStackModeToggle extends StatelessWidget {
  static const surfaceKey = ValueKey('image-stack-mode-surface');
  static const glyphKey = ValueKey('image-stack-mode-glyph');
  static const visibleSize = 28.0;
  static const glyphSize = 22.0;
  static const touchSize = 44.0;
  static const _cardRadius = 2.0;

  final bool expanded;
  final VoidCallback onPressed;
  final int total;

  /// The gallery supplies its live progress to keep photos and icon in sync,
  /// including when the user reverses an unfinished transition.
  final double? progress;

  const ImageStackModeToggle({
    super.key,
    required this.expanded,
    required this.onPressed,
    required this.total,
    this.progress,
  });

  Widget _glyph(BuildContext context, double value) {
    final t = AppTokens.of(context);
    final p = value.clamp(0.0, 1.0);
    return SizedBox.square(
      key: glyphKey,
      dimension: glyphSize,
      child: Stack(
        // Retain the middle rectangle in front throughout the morph.
        children: [
          for (final i in const [0, 2, 1])
            Positioned.fill(
              child: Center(
                child: Transform.translate(
                  key: ValueKey('image-stack-mode-card-$i'),
                  offset: Offset(
                    (i - 1) * 2.6 * (1 - p),
                    .5 * (1 - p) + (i - 1) * 6 * p,
                  ),
                  child: Transform.rotate(
                    angle: (i - 1) * .34 * (1 - p),
                    child: RepaintBoundary(
                      child: SizedBox(
                        key: ValueKey('image-stack-mode-rect-$i'),
                        width: 8 + 8 * p,
                        height: 12 - 10 * p,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Color.lerp(t.surface, t.text2, p),
                            borderRadius: BorderRadius.circular(
                              _cardRadius - p,
                            ),
                            border: Border.all(
                              color: t.text2,
                              width: AppSpace.hairline,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final reduced = MediaQuery.disableAnimationsOf(context);
    final label = expanded ? '收起为堆叠卡片' : '展开全部 $total 张';
    return Semantics(
      toggled: expanded,
      child: PressScale(
        onTap: onPressed,
        semanticLabel: label,
        child: SizedBox.square(
          dimension: touchSize,
          child: Center(
            child: DecoratedBox(
              key: surfaceKey,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: t.glass,
                border: Border.all(
                  color: t.separator,
                  width: AppSpace.hairline,
                ),
              ),
              child: SizedBox.square(
                dimension: visibleSize,
                child: Center(
                  child: progress != null
                      ? _glyph(context, progress!)
                      : TweenAnimationBuilder<double>(
                          tween: Tween(end: expanded ? 1.0 : 0.0),
                          duration: reduced
                              ? AppMotion.reducedFade
                              : AppMotion.curveOf(AppMotion.select).duration,
                          curve: reduced
                              ? Curves.easeOut
                              : AppMotion.curveOf(AppMotion.select),
                          builder: (context, value, _) =>
                              _glyph(context, value),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
